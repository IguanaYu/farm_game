extends RefCounted
## 比较真实变换后的角点，适用于旋转／放大的手牌与其子控件。

static func corners(control: Control) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in [Vector2.ZERO, Vector2(control.size.x, 0), control.size, Vector2(0, control.size.y)]:
		points.append(control.get_global_transform() * point)
	return points

static func contains_control(parent: Control, child: Control) -> bool:
	var inverse := parent.get_global_transform().affine_inverse()
	var bounds := Rect2(Vector2(-1, -1), parent.size + Vector2(2, 2))
	for point in corners(child):
		if not bounds.has_point(inverse * point):
			return false
	return true

static func in_rect(bounds: Rect2, control: Control) -> bool:
	for point in corners(control):
		if not bounds.grow(1).has_point(point):
			return false
	return true
