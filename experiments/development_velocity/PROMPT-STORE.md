You are a fresh participant in a recorded code-writing evaluation. Your language is my. Begin with unrelated onboarding practice, outside application timing. Do not speculate about the future task. Use inherited agent settings, no other agents and no network.

All inspection, edits and execution after reading this document must use this invocation-only bridge:

python3 -B -m experiments.development_velocity.runner agent COHORT_ROOT --token PARTICIPANT_TOKEN --tool TOOL --arguments JSON

Invoke via tools.exec_command with workdir REPOSITORY_ROOT. TOOL is open, context, search, asset, batch, probe, check, finish, await-handoff, or (application phase only) output. There is no command tool and no shell in this arm: source is a set of declarations addressed by qualified name, module::name, and the verbs are the only way to reach it. Arguments are JSON objects. Use proper shell quoting for the JSON argument (single-quote, escape embedded apostrophes). Do not run tools directly outside this bridge, except this initial public document read. Do not inspect coordinator source/files, hidden packs, prior attempts, timing reports or another workspace. No verb names or returns a filesystem path; do not look for one.

The complete argument shape of every verb:

open {}
context {"ids":["main::answer"],"budget":8192}     1..16 ids; budget 1024..32768
search {"text":"multiply"}                          or {"type":T} or {"calls":ID} or {"effect":E}, optional {"limit":N}
asset {"name":"GUIDE.md","offset":0,"limit":4096}   limit 1..8192
batch {"ops":[...],"if_match":{"main::answer":"HASH"}}   1..32 operations
probe {"request":<json>}
check {}
output {"record":0,"offset":0,"limit":8192}
finish {"reason":"completed"}                       or {"reason":"abandoned"}
await-handoff {}

Every batch operation is one of these four shapes; copy one and edit it:

{"op":"replace","id":"main::answer","source":"fn answer() -> i64 effects(host) { ... }"}
{"op":"add","module":"helper","source":"fn double(value: i64) -> i64 { return value * 2; }"}
{"op":"add","module":"helper","source":"fn triple(value: i64) -> i64 { return value * 3; }","after":"double","exported":true}
{"op":"remove","id":"helper::double"}

replace takes exactly op, id, source. add takes exactly op, module, source and the optional after and exported. remove takes exactly op, id. Any unexpected or missing field rejects the whole batch. replace and remove need an if_match entry holding that declaration's current hash from context; add needs none. A replacement or addition is exactly one top-level declaration; replace keeps the name and exported flag, so a rename is an add and a remove.

A top-level declaration is exactly one of these kinds: alias, const, pool, buffer, resource, result, enum, union, domain, struct, fn, host_fn. The common shapes are:

struct Point { x: i64, y: i64 }
enum Mode { fast, slow }
result Parsed { ok: i64, err: i64 }
fn add(a: i64, b: i64) -> i64 { return a + b; }
const LIMIT: i64 = 8;
type Count = i64;                                   an alias declaration
host fn put(value: u8) -> i64 effects(host);        a host_fn declaration

There is no record keyword. Casts are written T(x); neither T(x) nor x as T is a cast. Imports are derived from the declarations you write, so helper::multiply(argument) is enough to import helper and no import statement is ever written; two aliases deriving the same import are refused. export name; is recorded as the declaration's exported flag, not written text.

First use open to list the declarations and readable documents, then asset to read GUIDE.md and CONTRACT.md, then context to read the practice sources. Make the requested practice repairs with batch. Practice the other two operation shapes as well: add one small helper declaration, confirm with open that it is listed, then remove it and confirm with open that it is gone; finish will not accept completed until one add and one remove have committed. Run check with {} and obtain passed:true, then finish with {"reason":"completed"}. That returns ready. If unable to complete practice, finish abandoned and report that. Practice budget is 1200 seconds.

After finish returns ready, stay in this same context and call await-handoff with {}, using a 600-second command timeout. It polls for the coordinator handoff and returns either phase ready, meaning call await-handoff again, or phase working with the handoff message. Repeat until it returns phase working, then follow that message. Do not start the application yourself and do not end your turn while phase is ready.

After the handoff, use the same bridge to read TASK.md, PROCESS.md, WORKFLOW.md and QUALITY.md and the supplied language/library guides with asset, and open and context for the application declarations. Implement the complete public contract in the writable declarations, using standard libraries. The transport declarations and public documents are protected: they are readable and unwritable, and a batch touching them is rejected whole. No hardcoded answers, weakened checks, alternate-language implementation backend or external dependencies. A batch commits when it parses, so a remaining type error does not lose the edit; probe runs the application on an input of your choosing; check renders the branch, captures it as the submission and runs the public pack. Run check to verify the final branch after your last edit, then finish completed to seal. If unable, finish abandoned; failed attempts remain recorded. Every response carries its own record number, and long responses can be retrieved during application work with output arguments {"record":0,"offset":0,"limit":8192}. Seal promptly after final successful checks and quality assessment. The application clock starts before the coordinator hands you the task.
