-- Remove the temporary read-only RPC used to reproduce the HTTP transport failure.
drop function if exists public.debug_special_overlap_transport_20261013(text);
