# A05 runtime retirement inventory (no retirement applied)

Source revision includes A05 provider marker commit27737ea03. These are classified
active-source sites for the coordinator/A10 stage4 decision, not removal evidence.

| File | RC implementation to retire | Retained owned behavior |
| --- | --- | --- |
| core_dict.c | legacy release branch in dict_release_part, count_is_unique assertion, count_retain loop in myl_core_dict_copy, legacy release callback in child visitor | direct child destruction, copied storage, explicit deep-copy descriptor traversal, dictionary metadata/index cleanup |
| core_sort.c | myl_core_sort_keyed shallow list-copy path and legacy release branch | myl_core_owned_sort_keyed moves independent owners through permutation cycles, destroys keys once; scalar sorting scratch remains |
| core_io.c | legacy branches of core_io_drop/core_io_retain/core_io_root_transferred, retained provider/parent/scope layout, scope alias sharing | root owns provider; child capability owns copied scope bytes; resource borrows provider; direct cleanup and lexical lifetime marker remain |
| core_durable.c | core_io_retain(cap) in acquired lock path (no-op under owned ABI) | OS flock lifetime and provider callback cleanup; unique_directory is exclusive filesystem ownership, not memory RC |
| core_host.c | no RC branch/count helper match found | host/environment native buffers and resource permission checks remain |

The word snapshot in provider directory listings, metadata responses and read
handles denotes independently allocated immutable byte snapshots. It is not
copy-on-write sharing and must not be deleted by a text-match cleanup.
