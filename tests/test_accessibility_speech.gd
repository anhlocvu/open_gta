extends SceneTree
## Headless TDD suite for NVDA-only speech core, settings persistence, priority queue, and history.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + msg)
	else:
		failures += 1
		push_error("FAIL: " + msg)

func run() -> void:
	var wrapper_src := FileAccess.get_file_as_string("res://addons/nvda_integration/NvdaWrapper.gd")
	var speech_src := FileAccess.get_file_as_string("res://scripts/accessibility/a11y_speech.gd")
	check(not wrapper_src.contains("DisplayServer.tts_"), "NvdaWrapper strictly excludes SAPI DisplayServer TTS")
	check(not speech_src.contains("DisplayServer.tts_"), "A11ySpeech strictly excludes SAPI DisplayServer TTS")
	check(not wrapper_src.contains("has_singleton(\"NVDA\")"), "NvdaWrapper resolves ClassDB NVDA static API instead of broken Engine.has_singleton")
	check(not speech_src.contains("has_singleton(\"NVDA\")"), "A11ySpeech resolves ClassDB NVDA static API instead of broken Engine.has_singleton")

	var WrapperScript := load("res://addons/nvda_integration/NvdaWrapper.gd")
	var wrapper: Node = WrapperScript.new()
	root.add_child(wrapper)
	await process_frame
	check(wrapper.has_method("has_nvda_extension") and wrapper.has_nvda_extension() == ClassDB.class_exists(&"NVDA"), "NvdaWrapper detects loaded NVDA ClassDB extension cleanly")
	wrapper.queue_free()
	await process_frame

	var SpeechScript := load("res://scripts/accessibility/a11y_speech.gd")
	var speech: Node = SpeechScript.new()
	root.add_child(speech)
	await process_frame

	var spoken_calls: Array[String] = []
	var cancel_calls := [0]
	var nvda_up := [true]
	speech.set_mock_backend(
		func() -> bool: return nvda_up[0],
		func(txt: String) -> void: spoken_calls.append(txt),
		func() -> void: cancel_calls[0] += 1
	)

	check(speech.speak("Main menu", true, speech.Priority.HIGH), "speak succeeds when NVDA running")
	check(spoken_calls == ["Main menu"] and cancel_calls[0] == 1, "interrupt cancels then speaks via NVDA backend")
	check(not speech.speak("Main menu", true, speech.Priority.HIGH), "dedup suppresses identical rapid repeat")
	check(speech.speak("Main menu", true, speech.Priority.HIGH, &"general", true), "force flag bypasses dedup")

	speech.speak("First queued", false, speech.Priority.NORMAL, &"cat1")
	speech.speak("Second queued", false, speech.Priority.NORMAL, &"cat2")
	check(spoken_calls.size() == 2 and speech._queue.size() == 2, "queued non-interrupt speech waits when busy")
	speech.speak("Urgent hit", true, speech.Priority.CRITICAL, &"combat")
	check(spoken_calls.back() == "Urgent hit", "critical interrupt speaks immediately")

	speech.clear_history()
	speech.speak("Line one", true, speech.Priority.NORMAL, &"h1", true)
	speech.speak("Line two", true, speech.Priority.NORMAL, &"h2", true)
	speech.speak("Line three", true, speech.Priority.NORMAL, &"h3", true)
	check(speech.get_history() == ["Line one", "Line two", "Line three"], "history stores ordered unique announcements")
	check(speech.review_previous() == "Line two", "review_previous steps back cleanly")
	check(speech.review_previous() == "Line one", "review_previous reaches oldest item")
	check(speech.review_next() == "Line two", "review_next advances cursor")
	check(speech.repeat_last() == "Line three", "repeat_last jumps to newest entry")
	check(speech.get_history().size() == 3, "history review does not pollute history")

	nvda_up[0] = false
	var count_before := spoken_calls.size()
	speech.speak("NVDA offline test", true, speech.Priority.HIGH, &"off", true)
	check(spoken_calls.size() == count_before, "when NVDA offline, no speech call or SAPI fallback occurs")
	check(speech.get_history().back() == "NVDA offline test", "history still retains line when NVDA temporarily offline")

	var cfg := ConfigFile.new()
	var s := A11ySettings.new()
	s.snap_turn_degrees = 90.0
	s.aim_assist_enabled = false
	s.cue_volume = 0.45
	s.save_to_config(cfg)
	var s2 := A11ySettings.new()
	s2.load_from_config(cfg)
	check(is_equal_approx(s2.snap_turn_degrees, 90.0) and not s2.aim_assist_enabled and is_equal_approx(s2.cue_volume, 0.45), "A11ySettings round-trips through ConfigFile")

	speech.queue_free()
	await process_frame
	print("ACCESSIBILITY_SPEECH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
