class_name TempCorpusFromDamage
extends Mechanic
## Gives the owner temporary Corpus equal to a fraction of the damage they deal.

@export_range(0.0, 5.0, 0.05) var fraction: float = 1.0
## 0 = no cap on total temporary Corpus.
@export var max_temp_corpus: int = 0


func on_damage_dealt(owner: StatBlock, event: DamageEvent) -> void:
	if owner == null or event.dealt <= 0:
		return
	owner.add_temp_corpus(floori(event.dealt * fraction), max_temp_corpus)
