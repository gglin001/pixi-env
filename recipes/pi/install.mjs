import { existsSync, readdirSync, rmSync } from "node:fs";
import { resolve, join } from "node:path";
import { packReleasePackages, installCodingAgentConsumer, smokeTestCodingAgentConsumer } from "./scripts/coding-agent-consumer.mjs";
import { getPublicWorkspacePackages } from "./scripts/release-packages.mjs";

const runtimePackages = new Set([
  "@earendil-works/chord",
  "@earendil-works/pi-tui",
  "@earendil-works/pi-telemetry",
  "@earendil-works/pi-ai",
  "@earendil-works/pi-agent-core",
  "@earendil-works/pi-coding-agent",
]);
const packages = getPublicWorkspacePackages().filter(({ name }) => runtimePackages.has(name));
const tarballs = packReleasePackages(packages, resolve("conda-packages"));
// Keep the consumer outside the checkout so missing dependencies cannot be
// resolved accidentally from the development node_modules directory.
const destination = join(process.env.PREFIX, "lib/pi");
installCodingAgentConsumer(destination, tarballs);

// The Darwin build produces both architectures. Keep only the current target.
const native = join(destination, "node_modules/@earendil-works/pi-tui/native");
for (const platform of ["darwin", "linux", "win32"]) {
  const prebuilds = join(native, platform, "prebuilds");
  if (!existsSync(prebuilds)) continue;
  for (const arch of readdirSync(prebuilds)) {
    if (platform !== process.platform || arch !== `${process.platform}-${process.arch}`) {
      rmSync(join(prebuilds, arch), { recursive: true, force: true });
    }
  }
}
smokeTestCodingAgentConsumer(destination);
// These install-only manifests reference tarballs in the build directory.
for (const file of ["package.json", "package-lock.json", "node_modules/.package-lock.json"]) {
  rmSync(join(destination, file), { force: true });
}
