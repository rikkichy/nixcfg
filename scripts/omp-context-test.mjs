import assert from "node:assert/strict";
import { executionContext } from "../common/dotfiles/omp/nixcfg-execution.js";

assert.match(executionContext({}, false), /^local\b/);
assert.equal(executionContext({ SSH_CONNECTION: "fixture" }, false), "SSH");
assert.equal(executionContext({}, true), "container");
assert.equal(executionContext({ container: "podman" }, false), "container");
assert.equal(executionContext({ SSH_CLIENT: "fixture", container: "docker" }, false), "container + SSH");
console.log("PASS: local, SSH, container markers/environment and combined execution contexts");
