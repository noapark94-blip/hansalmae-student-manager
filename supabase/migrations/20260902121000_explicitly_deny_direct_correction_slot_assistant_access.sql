create policy correction_slot_assistants_rpc_only
on public.correction_slot_assistants
for all
to authenticated
using (false)
with check (false);
