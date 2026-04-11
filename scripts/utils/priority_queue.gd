class_name PriorityQueue
extends RefCounted
## Minimal binary min-heap priority queue for A* and other search algorithms.
## Items are arbitrary values keyed by a float / int priority (smallest pops first).
##
## Usage:
##   var pq := PriorityQueue.new()
##   pq.push("start", 0)
##   var item = pq.pop()

## Internal storage — each entry is [priority, value].
var _heap: Array = []


func push(value: Variant, priority: float) -> void:
	_heap.append([priority, value])
	_sift_up(_heap.size() - 1)


func pop() -> Variant:
	if _heap.is_empty():
		return null
	var root: Array = _heap[0]
	var last: Array = _heap.pop_back()
	if not _heap.is_empty():
		_heap[0] = last
		_sift_down(0)
	return root[1]


func peek() -> Variant:
	if _heap.is_empty():
		return null
	return _heap[0][1]


func is_empty() -> bool:
	return _heap.is_empty()


func size() -> int:
	return _heap.size()


func clear() -> void:
	_heap.clear()


func _sift_up(idx: int) -> void:
	while idx > 0:
		@warning_ignore("integer_division")
		var parent: int = (idx - 1) / 2
		if float(_heap[idx][0]) < float(_heap[parent][0]):
			var tmp = _heap[idx]
			_heap[idx] = _heap[parent]
			_heap[parent] = tmp
			idx = parent
		else:
			break


func _sift_down(idx: int) -> void:
	var n: int = _heap.size()
	while true:
		var left: int = idx * 2 + 1
		var right: int = idx * 2 + 2
		var smallest: int = idx
		if left < n and float(_heap[left][0]) < float(_heap[smallest][0]):
			smallest = left
		if right < n and float(_heap[right][0]) < float(_heap[smallest][0]):
			smallest = right
		if smallest == idx:
			break
		var tmp = _heap[idx]
		_heap[idx] = _heap[smallest]
		_heap[smallest] = tmp
		idx = smallest
