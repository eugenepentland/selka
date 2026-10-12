# Optional C1 owned-component pin forwarding

The coordinator applied the root patch to the worker tree for qualification;
integration is pending. It adds an optional
`-Dcomponent-owned-compiler-pin=FILE` and forwards that same file to component
provisioning and `test_component_native.py`. `component-seed-source` is also
forwarded to both requests. Absolute paths use Zig's cwd-relative LazyPath;
relative paths remain relative to the build root. Without an explicit pin, the
historical selection stays unchanged. `component-builder` and `seed-compiler`
remain independent of component provisioning. No real pin is invented here.

The manifest input recipes use `selfhost/component-*.json`, covering both the
unchanged historical seed and the eventual new owned compiler manifest. The
native qualification script is added to the component-builder test closure
because its report/routing tests now import that script. A selected external
pin/archive is a declared file input of each corresponding Zig run step;
component preparation remains an always-fresh verification action, and installed
component identities bind the full selected seed recipe.

The native qualification companion now:

- Passes a supplied archive through its seed-only request, so a fresh/offline
  qualification does not unexpectedly require a Git archive already present.
- Binds `MYLANG_COMPONENT_DIR` to the already-provisioned candidate component
  directory. The source-only compiler has no installed libexec siblings. Its
  guest tests run after component provisioning; no host compiler is substituted.
- Checks each installed artifact's digest and, for the owned route, its memory
  mode before using it in test discovery/protocol operations.
- Requires the actual `native-tests-v1` verdict list and exact counts, with no
  failed/unsupported/skipped tests and at least one pass. A successful process
  exit with unsupported tests cannot qualify the package. The general CLI exit
  contract remains unchanged.

The optional root component-builder target passes 3/3 steps in an isolated
prefix without provisioning a seed; its native coordinator hash is unchanged.
Four focused report/routing tests pass; the complete fake-tool suite passes
25/25. These test orchestration and refusal behavior, not a real installed owned
package. The mock routing test covers one pin/archive, all four guest-test calls,
all six build/protocol calls and the explicit candidate component environment.
The old `selfhost/component-seed.json` SHA256 is still
`a2e02f86f24b139c1b3b71c035ad0f376246f43b12081f3f5beac1bbc007da1c`.

After cache-plan compiles and both source/protocol/ABI contracts qualify, the
coordinator can archive the actual integrated compiler commit and create its new
manifest. Run the `components` and `test-components` targets with that same real
pin/archive and an isolated install prefix under shared admission. Record the
source archive, built compiler, component artifacts, manifests, counted protocol
runs and symbol/LLVM audits. Then qualify the full installation and ordinary
commands. The pin's seed-compiler step builds only the compiler; its subsequent
`build` commands produce the components before tests need those components.

C2 promotion and C3 retirement remain separate. The C1 route passes the existing
zero-RC selector to its independent compiler. Retirement needs an ordinary-owned
compiler pin and selector-free builder recipe, plus deletion of active historical
fallback selection. An optional route alone does not retire RC.
