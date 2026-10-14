# Before You Upgrade

This bundle was generated for the `terraform` deployer. The steps below apply only
when this bundle is applied over an existing installation of an earlier version.
A fresh install can skip this file.

Each entry covers only the boundary this bundle's pinned version lands in. To
check your exact move, including any earlier boundary you would cross, run
`aicr upgrade-check` against the recipe you deployed from.

## nodewright-operator: manual

This bundle pins `v0.19.0`. Applies when upgrading from `<0.18.0` into `>=0.18.0 <=0.19.1`.

v0.18.0 renames skyhook.nvidia.com/v1alpha1 Skyhook to nodewright.nvidia.com/v1alpha1 NodeWright, moves DeploymentPolicy to the same group, and shifts the on-node annotation, label and finalizer prefix. An operator-side mirror migrates the objects for you, but completion status is then written only on the new kind and the attempt to mirror it back to the legacy object fails in a reconcile conflict loop, so Skyhook.status stays empty forever on a cluster where tuning has genuinely finished. Anything still reading the legacy status waits on a value that never arrives. The legacy object also goes read-only: the post-rename admission webhook rejects any spec, pause or disable change to it, so the first attempt to alter tuning after the upgrade fails rather than the cluster merely reporting the wrong status. Deletions and identical re-applies are still accepted, which is why a steady-state sync keeps working and the break only surfaces on a real edit.

**Before you start:** Every Skyhook is complete with no nodes in progress. Upstream makes this a requirement rather than a recommendation: the migration relabels the operator's package and per-node ConfigMaps so the post-rename operator adopts them instead of recreating them, and that flow assumes no in-flight package work to disrupt. Check with `kubectl get skyhooks.skyhook.nvidia.com -o custom-columns=NAME:.metadata.name,STATUS:.status.status,INPROGRESS:.status.nodesInProgress` and proceed only when nothing is actively rolling out. paused and disabled objects are fine to leave as they are — the mirror carries that state onto the NodeWright — but do not unpause or enable one until its pre-upgrade package pods are gone.

**Reversible:** no.

**Steps for terraform:**

1. `expect-operator-downtime-during-the-hook`: The chart runs a selector-migration pre-upgrade hook that DELETES the operator Deployment before helm recreates it. If that hook's Job fails or exceeds its deadline, helm aborts the upgrade with the Deployment already gone, so the namespace is left with no operator at all and the release sits in `failed`. Re-run the same helm upgrade to recover; it completes once the hook Job passes.\
   *Why:* Observed on a kind cluster crossing v0.17.1 to v0.19.0: the hook pod exited 0 having deleted the Deployment, but the Job tripped its activeDeadlineSeconds while its image was still being pulled, and helm treated the Job failure as an aborted upgrade. The deletion is deliberate: the hook deletes when the live selector would have to change (spec.selector is immutable) or when the running operator predates label-based webhook discovery, which is what fired here. Such an operator looks its webhook configurations up by name, the upgrade renames them, so it never goes Ready, never releases the webhook bootstrap lease and is never terminated by the rolling update, wedging the release on "Pending termination". A short operator gap is the cheaper failure. The exposure is that gap widening, not the deletion.
2. `upgrade-operator`: helm upgrade the operator chart, before touching any CR.\
   *Why:* The chart ships both groups' CRDs and RBAC, and the mirror imports each Skyhook into a NodeWright. Per-node state is copied to the nodewright.nvidia.com/* prefix, so packages are not re-run.
3. `rename-crs`: Rewrite your CR manifests and apply them: sed -e '/^ *apiVersion:/ s|skyhook\.nvidia\.com/|nodewright.nvidia.com/|' -e 's|^\( *kind: *\)Skyhook[[:space:]]*$|\1NodeWright|' my-skyhook.yaml > my-nodewright.yaml\
   *Why:* The mirror already created the object, so this applies as a no-op adoption rather than a fresh create. Rewrite apiVersion and kind only: a blanket substitution also rewrites nodeSelectors and podNonInterruptLabels, which name your labels rather than the operator's, and that turns a no-op adoption into a real spec change against keys nothing carries.
4. `delete-legacy-crs`: Once the NodeWright exists and reconciles: kubectl delete skyhook.skyhook.nvidia.com <name>, then kubectl delete deploymentpolicy.skyhook.nvidia.com <name>.\
   *Why:* Skyhooks must go before the DeploymentPolicy they reference. The NodeWright survives, because the mirror never deletes it. Legacy per-node state and pre-rename package pods are kept for the LEGACY_CLEANUP_DELAY rollback window and pruned later, not now. Do not remove the skyhook.nvidia.com CRD itself until every legacy object is gone, since that cascade-deletes whatever remains.
5. `verify-migration`: kubectl get nodewrights.nodewright.nvidia.com lists a NodeWright for each former Skyhook, node annotations are present under the nodewright.nvidia.com/ prefix, and no package re-ran.\
   *Why:* Confirms the mirror adopted live lifecycle position rather than handing the new object a fresh rollout.

**References:**

- https://github.com/NVIDIA/nodewright/blob/main/docs/getting-started/migration.md
- https://github.com/NVIDIA/nodewright/blob/main/docs/getting-started/migration.md#prerequisite-all-skyhooks-must-be-complete
- https://github.com/NVIDIA/aicr/blob/main/docs/user/component-catalog.md#nodewright-operator-v0180-renames-skyhook-to-nodewright
- https://github.com/NVIDIA/aicr/issues/2593
- https://github.com/NVIDIA/aicr/issues/2594
