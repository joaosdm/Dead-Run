class_name HighScoreManager
extends RefCounted

## Dead Run - High Score & Persistence System (Godot 4.3)
## Gerencia o salvamento e carregamento local de recordes via ConfigFile ("user://highscore.save").
## Registra maior distância, maior pontuação, total de zumbis eliminados, headshots e tempo de sobrevivência.

const SAVE_PATH: String = "user://highscore.save"
const SECTION_RECORDS: String = "records"
const SECTION_SETTINGS: String = "settings"

static var _cached_records: Dictionary = {}
static var _is_loaded: bool = false


## Carrega ou inicializa os dados salvos em disco
static func _ensure_loaded() -> void:
	if _is_loaded:
		return

	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)

	_cached_records = {
		"best_distance": 0.0,
		"best_score": 0,
		"best_kills": 0,
		"best_headshots": 0,
		"best_survival_time": 0.0,
		"total_runs": 0,
		"campaign_completed": false,
		"unlocked_nightmare": true ## Permitir acesso ao modo Pesadelo diretamente ou via campanha
	}

	if err == OK:
		_cached_records["best_distance"] = config.get_value(SECTION_RECORDS, "best_distance", 0.0)
		_cached_records["best_score"] = config.get_value(SECTION_RECORDS, "best_score", 0)
		_cached_records["best_kills"] = config.get_value(SECTION_RECORDS, "best_kills", 0)
		_cached_records["best_headshots"] = config.get_value(SECTION_RECORDS, "best_headshots", 0)
		_cached_records["best_survival_time"] = config.get_value(SECTION_RECORDS, "best_survival_time", 0.0)
		_cached_records["total_runs"] = config.get_value(SECTION_RECORDS, "total_runs", 0)
		_cached_records["campaign_completed"] = config.get_value(SECTION_RECORDS, "campaign_completed", false)
		_cached_records["unlocked_nightmare"] = config.get_value(SECTION_SETTINGS, "unlocked_nightmare", true)

	_is_loaded = true


## Retorna o recorde de distância percorrida (em metros)
static func get_best_distance() -> float:
	_ensure_loaded()
	return float(_cached_records.get("best_distance", 0.0))


## Retorna o recorde de pontuação
static func get_best_score() -> int:
	_ensure_loaded()
	return int(_cached_records.get("best_score", 0))


## Retorna o total de eliminações no recorde
static func get_best_kills() -> int:
	_ensure_loaded()
	return int(_cached_records.get("best_kills", 0))


## Retorna se o modo pesadelo está liberado
static func is_nightmare_unlocked() -> bool:
	_ensure_loaded()
	return bool(_cached_records.get("unlocked_nightmare", true))


## Retorna um dicionário com todos os recordes consolidados
static func get_all_records() -> Dictionary:
	_ensure_loaded()
	return _cached_records.duplicate()


## Salva os resultados de uma corrida e retorna métricas indicando se houve novo recorde
static func save_run_result(
	distance: float,
	score: int,
	kills: int,
	headshots: int,
	survival_time: float,
	campaign_won: bool = false
) -> Dictionary:
	_ensure_loaded()

	var prev_distance: float = float(_cached_records.get("best_distance", 0.0))
	var prev_score: int = int(_cached_records.get("best_score", 0))

	var is_new_distance: bool = distance > prev_distance
	var is_new_score: bool = score > prev_score

	if is_new_distance:
		_cached_records["best_distance"] = distance

	if is_new_score:
		_cached_records["best_score"] = score

	if kills > int(_cached_records.get("best_kills", 0)):
		_cached_records["best_kills"] = kills

	if headshots > int(_cached_records.get("best_headshots", 0)):
		_cached_records["best_headshots"] = headshots

	if survival_time > float(_cached_records.get("best_survival_time", 0.0)):
		_cached_records["best_survival_time"] = survival_time

	_cached_records["total_runs"] = int(_cached_records.get("total_runs", 0)) + 1

	if campaign_won:
		_cached_records["campaign_completed"] = true
		_cached_records["unlocked_nightmare"] = true

	# Grava no arquivo físico
	var config := ConfigFile.new()
	for key in ["best_distance", "best_score", "best_kills", "best_headshots", "best_survival_time", "total_runs", "campaign_completed"]:
		config.set_value(SECTION_RECORDS, key, _cached_records[key])

	config.set_value(SECTION_SETTINGS, "unlocked_nightmare", _cached_records["unlocked_nightmare"])
	config.save(SAVE_PATH)

	return {
		"is_new_distance": is_new_distance,
		"is_new_score": is_new_score,
		"previous_distance": prev_distance,
		"previous_score": prev_score,
		"current_distance": distance,
		"current_score": score,
		"current_kills": kills,
		"current_headshots": headshots
	}
