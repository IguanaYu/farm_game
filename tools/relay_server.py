#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""小小农场·房号中继服务（互联网联机，内测版）。

协议：NDJSON over TCP——一行一条 UTF-8 JSON。
  客户端 → 服务器：
    {"t":"create_room"}                       创建房间（成为成员 1/主机）
    {"t":"join_room","code":"482913"}         加入房间（成为成员 2/客机）
    {"t":"relay","body":{...}}                游戏层消息，转发给房间另一成员
    {"t":"_transport_ping"}                   传输层心跳
    {"t":"leave_room"}                        主动退房并断开
  服务器 → 客户端：
    {"t":"room","code":"482913"}              房号（对 create_room 的应答）
    {"t":"joined","code":"482913"}            已加入（对 join_room 的应答）
    {"t":"relay","from":1|2,"body":{...}}     转发的游戏层消息（from=发送方成员编号）
    {"t":"peer_down","from":1|2}              对端断开（房间保留等待重连）
    {"t":"error","reason":"..."}              拒绝/错误
    {"t":"_transport_pong"}                   心跳应答

房间生命周期：创建即生效；成员断开仅置空槽位并通知对端；两槽皆空超过 TTL
（默认 10 分钟）后回收。房号 6 位数字，全局唯一。

用法：python3 relay_server.py --port 31970 [--room-ttl-min 10] [--rate-per-sec 50]
依赖：仅 Python 3 标准库（3.6+ 兼容）。
部署：见 docs/plan/Godot_联机中继_互联网房间_方案与执行计划_v0.1.md §8。
"""

import argparse
import asyncio
import json
import logging
import random
import time

log = logging.getLogger("farm-relay")

CONFIG = {
    "port": 31970,
    "room_ttl_s": 600.0,
    "rate_per_sec": 50.0,
}

RATE_BURST = 100.0        # 令牌桶容量（突发上限）
MAX_LINE_BYTES = 1000000  # 单行超长视为恶意/异常，断开


class Conn(object):
    """一条客户端连接（成员编号在加入房间后分配：主机=1，客机=2）。"""

    def __init__(self, reader, writer):
        self.reader = reader
        self.writer = writer
        self.bucket = [RATE_BURST, time.monotonic()]
        self.member_id = None
        self.room = None


class Room(object):
    def __init__(self, code):
        self.code = code
        self.members = {1: None, 2: None}
        self.last_active = time.monotonic()


ROOMS = {}


def make_code():
    while True:
        code = "%06d" % random.randint(0, 999999)
        if code not in ROOMS:
            return code


def other_id(member_id):
    return 2 if member_id == 1 else 1


async def send_line(conn, obj):
    if conn.writer.is_closing():
        return
    try:
        data = (json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
        conn.writer.write(data)
        await conn.writer.drain()
    except (ConnectionResetError, BrokenPipeError, OSError):
        pass


def consume_token(bucket):
    tokens, last = bucket
    tokens = min(RATE_BURST, tokens + (time.monotonic() - last) * CONFIG["rate_per_sec"])
    if tokens < 1.0:
        bucket[0] = 0.0
        bucket[1] = time.monotonic()
        return False
    bucket[0] = tokens - 1.0
    bucket[1] = time.monotonic()
    return True


async def detach(conn, notify_other=True):
    """连接结束：置空槽位、通知对端、保留房间等待重连。"""
    room = conn.room
    if room is not None and room.members.get(conn.member_id) is conn:
        room.members[conn.member_id] = None
        room.last_active = time.monotonic()
        peername = conn.writer.get_extra_info("peername")
        log.info("room %s member %s down (%s)", room.code, conn.member_id, peername)
        if notify_other:
            other = room.members.get(other_id(conn.member_id))
            if other is not None:
                await send_line(other, {"t": "peer_down", "from": conn.member_id})
    conn.room = None


async def handle(reader, writer):
    conn = Conn(reader, writer)
    peername = writer.get_extra_info("peername")
    log.info("conn from %s", peername)
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            if len(line) > MAX_LINE_BYTES:
                log.warning("oversized line from %s, drop conn", peername)
                break
            if not consume_token(conn.bucket):
                log.warning("rate limited %s, drop conn", peername)
                break
            try:
                message = json.loads(line.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                await send_line(conn, {"t": "error", "reason": "非 JSON 行"})
                continue
            if not isinstance(message, dict):
                await send_line(conn, {"t": "error", "reason": "消息必须是 JSON 对象"})
                continue
            kind = message.get("t")

            if kind == "create_room":
                if conn.room is not None:
                    await send_line(conn, {"t": "error", "reason": "已在房间中，先 leave_room"})
                    continue
                code = make_code()
                room = Room(code)
                room.members[1] = conn
                conn.member_id = 1
                conn.room = room
                ROOMS[code] = room
                await send_line(conn, {"t": "room", "code": code})
                log.info("room %s created by %s", code, peername)

            elif kind == "join_room":
                code = str(message.get("code", ""))
                room = ROOMS.get(code)
                if conn.room is not None:
                    await send_line(conn, {"t": "error", "reason": "已在房间中，先 leave_room"})
                elif room is None:
                    await send_line(conn, {"t": "error", "reason": "房间不存在或已过期"})
                elif room.members.get(2) is not None:
                    await send_line(conn, {"t": "error", "reason": "该房间已有客机在线"})
                else:
                    room.members[2] = conn
                    conn.member_id = 2
                    conn.room = room
                    room.last_active = time.monotonic()
                    await send_line(conn, {"t": "joined", "code": code})
                    log.info("room %s joined by %s", code, peername)

            elif kind == "relay":
                room = conn.room
                if room is None:
                    await send_line(conn, {"t": "error", "reason": "尚未加入房间"})
                    continue
                room.last_active = time.monotonic()
                other = room.members.get(other_id(conn.member_id))
                if other is not None:
                    await send_line(other, {"t": "relay", "from": conn.member_id, "body": message.get("body")})

            elif kind == "_transport_ping":
                await send_line(conn, {"t": "_transport_pong"})

            elif kind == "leave_room":
                await detach(conn)
                break

            else:
                await send_line(conn, {"t": "error", "reason": "未知消息类型: %s" % kind})
    except (asyncio.IncompleteReadError, ConnectionResetError, BrokenPipeError):
        pass
    except Exception:
        log.exception("conn error %s", peername)
    finally:
        await detach(conn)
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass


def gc_rooms():
    now = time.monotonic()
    dead = [code for code, room in ROOMS.items()
            if room.members[1] is None and room.members[2] is None
            and now - room.last_active > CONFIG["room_ttl_s"]]
    for code in dead:
        del ROOMS[code]
        log.info("room %s recycled (idle)", code)


async def maintenance_loop():
    while True:
        await asyncio.sleep(30)
        gc_rooms()
        active = sum(1 for r in ROOMS.values() if r.members[1] or r.members[2])
        log.info("stats: rooms=%d active=%d", len(ROOMS), active)


async def main():
    server = await asyncio.start_server(handle, "0.0.0.0", CONFIG["port"])
    asyncio.ensure_future(maintenance_loop())
    log.info("farm-relay listening on 0.0.0.0:%d", CONFIG["port"])
    async with server:
        await server.serve_forever()


def run():
    parser = argparse.ArgumentParser(description="小小农场·房号中继服务")
    parser.add_argument("--port", type=int, default=31970)
    parser.add_argument("--room-ttl-min", type=float, default=10.0)
    parser.add_argument("--rate-per-sec", type=float, default=50.0)
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args()
    CONFIG["port"] = args.port
    CONFIG["room_ttl_s"] = args.room_ttl_min * 60.0
    CONFIG["rate_per_sec"] = args.rate_per_sec
    logging.basicConfig(level=getattr(logging, args.log_level.upper(), logging.INFO),
                        format="%(asctime)s %(levelname)s %(message)s")
    # 兼容 3.6（无 asyncio.run）：手工事件循环。
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        loop.run_until_complete(main())
    except KeyboardInterrupt:
        log.info("bye")


if __name__ == "__main__":
    run()
