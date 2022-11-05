@tool
extends Node

const mutex_lock_const = preload("res://addons/gd_util/mutex_lock.gd")

var _loading_tasks_mutex: Mutex = Mutex.new()

signal task_set_stage(p_task_name, p_stage)
signal task_set_stage_count(p_task_name, p_stage_count)
signal task_done(p_task_name, p_err, p_resource)

class LoadingTask:
	extends RefCounted
	var load_path: String # the path is how you request status.
	var type_hint: String
	var bypass_whitelist: bool
	var external_path_whitelist: Dictionary
	var type_whitelist: Dictionary
	var cancelled: bool = false

	func _init(p_type_hint: String):
		type_hint = p_type_hint


func request_loading_task(p_path: String, p_external_path_whitelist: Dictionary, p_type_whitelist: Dictionary, p_type_hint: String = "") -> int:	
	print("request_loading_task: %s"% [p_path])
	var new_loading_task: LoadingTask = LoadingTask.new(p_type_hint)
	new_loading_task.bypass_whitelist = false
	new_loading_task.external_path_whitelist = p_external_path_whitelist
	new_loading_task.type_whitelist = p_type_whitelist
	var request : Callable
	request.bind("_request_loading_task_internal", p_path, new_loading_task)
	return WorkerThreadPool.add_task(request, false, "request_loading_task")


func request_loading_task_bypass_whitelist(p_path: String, p_type_hint: String = "") -> int:
	print("request_loading_task_bypass_whitelist: %s"% [p_path])
	var new_loading_task: LoadingTask = LoadingTask.new(p_type_hint)
	new_loading_task.bypass_whitelist = true
	var request : Callable
	request.bind("_request_loading_task_internal", p_path, new_loading_task)
	return WorkerThreadPool.add_task(request, false, "request_loading_task_bypass_whitelist")

func _request_loading_task_internal(p_path: String, p_new_loading_task: LoadingTask) -> void:	
	var _mutex_lock = mutex_lock_const.new(_loading_tasks_mutex)
	print("_request_loading_task_internal: %s"% [p_path])
	print_debug("background_load_path_request_loading_task: {path}".format({"path": str(p_path)}))
	var loading_task: LoadingTask = p_new_loading_task
	var path = p_path
	if not p_new_loading_task.load_path.is_empty():
		path = p_new_loading_task.load_path
	if loading_task.bypass_whitelist:
		print("Load " + str(p_path) + " of type " + str(loading_task.type_hint) + " **skip whitelist**")
		ResourceLoader.load_threaded_request(p_path, loading_task.type_hint)
	else:
		print("Load " + str(p_path) + " of type " + str(loading_task.type_hint) + " with " + str(loading_task.external_path_whitelist) + " and " + str(loading_task.type_whitelist))
		ResourceLoader.load_threaded_request_whitelisted(p_path, loading_task.external_path_whitelist, loading_task.type_whitelist, loading_task.type_hint)
	if p_path:
		loading_task.load_path = p_path
		task_set_stage_count.emit(p_path, 100) # now a percentage... was loader.get_stage_count()
	else:
		task_done.emit(p_path, ERR_FILE_UNRECOGNIZED, null)
	var status : int = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	var r_progress: Array = [].duplicate()
	status = ResourceLoader.load_threaded_get_status(path, r_progress)
	var resource : Resource = null
	resource = ResourceLoader.load_threaded_get(path)
	print(
		"background_loader_task_done: {task}, error: {err} resource_path: {resource_path}".format(
			{"task": str(p_path), "err":str(status), "resource": resource.resource_path}
		)
	)
	task_done.emit(p_path, status, resource)