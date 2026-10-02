# Suivre le coût et la qualité de la voix (EPIC-14, EPIC-16)

Vue `public.agent_step_stats` (lecture réservée au rôle `service_role` : éditeur SQL du tableau de bord Supabase ou `supabase db query --linked`). Une ligne par **étape × modèle de l’agent × semaine**.

```sql
select step, agent_model, week, turns, answered_turns, avg_cost_usd, total_cost_usd,
       avg_audio_seconds, avg_stt_ms, avg_agent_ms, invalid_output_rate,
       undone_rate, correction_rate, confirmations_asked, rejected_by_reason,
       cross_step_count, pending_accept_rate, notes_count
from public.agent_step_stats
order by week desc, step;
```

- `turns` compte toutes les lignes du journal (transcriptions, réponses locales « oui / non / annule », dictées d’adresse, récapitulatifs de pièces) ; `answered_turns` celles auxquelles l’agent a répondu.
- `undone_rate` : part des tours annulés par le vendeur (croix d’une pastille, « Annuler ce tour », « Annuler » de l’instantané, « annule » dit).
- `correction_rate` : part des tours contenant une correction (« non, plutôt 40 »).
- `rejected_by_reason` : rejets par motif (`quote_not_found`, `number_not_in_quote`, `anchor_missing`, `not_covered`, `ambiguous`…) ; un motif préfixé `x:` dans le journal concerne une valeur dite pour une autre étape.
- EPIC-16 : `cross_step_count` = valeurs dites pour une autre étape (réponses en attente créées), `pending_accept_rate` = acceptées / résolues (sur l’étape où elles ont été dites), `notes_count` = notes complémentaires retenues.

## Règle de réévaluation (plan §7.4)

Dès **200 tours réels pour une étape**, si l’un des seuils est franchi :

| Indicateur | Seuil |
|---|---|
| `undone_rate` | > 10 % |
| `correction_rate` | > 8 % |
| rejets `anchor_missing` + `number_not_in_quote` / tours répondus | > 15 % |
| `invalid_output_rate` | > 3 % |
| `pending_accept_rate` (EPIC-16) | < 70 % (trop de faux pré-remplissages : banc sur l’étape source) |

1. Rejouer le banc (`supabase/bench/`) sur cette étape avec le modèle candidat.
2. Basculer **cette étape seule**, sans republier l’app :

```sh
supabase secrets set OPENROUTER_MODEL_AGENT_ROOMS=anthropic/claude-haiku-4.5
# étapes : LOCATION, CONTEXT, TECHNICAL, ROOMS, LIFESTYLE (V1 sans voix depuis EPIC-16)
# transcription (toutes étapes) : OPENROUTER_MODEL_STT=mistralai/voxtral-mini-transcribe
```

3. Revenir au modèle commun : `supabase secrets unset OPENROUTER_MODEL_AGENT_ROOMS`.

Revue au plus tard à la fin de la phase de test.
