# Direct client permission cutoff — not deployed automatically

The SQL here is tested in disposable GitHub-hosted CI after the ordinary migrations.
It deliberately stays outside `supabase/migrations/`, which deploys automatically.

Promote it only in a separate authorized rollout after:

1. `20260909132922_backend_profile_reads.sql` and the profile API are deployed.
2. The native build using the profile API is installable and required for that channel.
3. Any admitted Apple review candidate also uses the profile API, and older backend instances have drained.
4. Staging sign-in, username onboarding, Fights, Steps, feedback, deletion, and update blocking have passed.

At promotion, generate a fresh migration timestamp with `supabase migration new`, move
the SQL into that migration, and update the database workflow. Replace the old pgTAP
expectations for direct client reads and profile/friendship writes with denial checks;
retain their privacy cases through `fitfight_backend_reader`. Move
`migration-tests/client-access-closed.sql` into the normal tests. Run the complete cloud
database suite before merging. Repeat the established staging-to-production process.

The cutoff revokes table and column permissions, sequences, app functions, and future
object defaults from ordinary clients. It preserves Supabase Auth/signup and the
server's Data API. Do not disable the Data API globally. After cutoff, a rollback must
use a backend that supports `fitfight_backend_reader` and the profile API.
