// Shared logic for the "Ready to merge" label.
//
// A pull request is ready when a committer (write or admin) approves the
// current head and no committer requests changes. The label is recomputed
// from the PR's live state, so every caller gets the same result.
//
// Used by:
//   - maintenance-label-on-approval.yml (after a review)
//   - maintenance-auto-label.yml        (after a push)
// Both callers run in concurrency group ready-label-<PR number>, so only
// one sync per PR runs at a time.

const LABEL = "Ready to merge";
const COMMENT = "✅ This PR has been reviewed and approved — all set for merge!";
// Removed on approval. "Work in progress" is owned by maintenance-label-wip.yml.
const REVIEW_LABELS = ["Needs review", "Backlog", "Can be closed?", "Help needed", "Needs Documentation"];

// Latest approval or change request of each committer.
// An approval counts only for the current head.
// A dismissal clears the reviewer's state; an older approval does not return.
async function evaluate(github, owner, repo, number) {
  const { data: pr } = await github.rest.pulls.get({ owner, repo, pull_number: number });
  const reviews = await github.paginate(github.rest.pulls.listReviews, {
    owner, repo, pull_number: number, per_page: 100,
  });
  const permission = Object.create(null);
  const state = Object.create(null);
  for (const r of reviews) {
    if (!r.user || !["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].includes(r.state)) continue;
    const login = r.user.login;
    if (!(login in permission)) {
      const { data } = await github.rest.repos.getCollaboratorPermissionLevel({ owner, repo, username: login });
      permission[login] = ["admin", "write"].includes(data.permission);
    }
    if (!permission[login]) continue;
    if (r.state === "DISMISSED") delete state[login];
    else if (r.state === "APPROVED" && r.commit_id !== pr.head.sha) delete state[login];
    else state[login] = r.state;
  }
  const states = Object.values(state);
  const approved = states.includes("APPROVED") && !states.includes("CHANGES_REQUESTED");
  return { approved, head: pr.head.sha, state };
}

// Add or remove the label to match the review state. Returns true when approved.
// On approval, also remove the review labels: a newer pending run can replace
// this run in the concurrency group, so every caller does the full cleanup.
async function syncOne({ github, core, owner, repo, number }) {
  const { approved, head, state } = await evaluate(github, owner, repo, number);
  core.info(`PR #${number} @ ${head}: committer reviews ${JSON.stringify(state)} -> approved=${approved}`);

  const { data: labels } = await github.rest.issues.listLabelsOnIssue({
    owner, repo, issue_number: number, per_page: 100,
  });
  const has = labels.some(l => l.name === LABEL);
  const remove = async () => {
    try {
      await github.rest.issues.removeLabel({ owner, repo, issue_number: number, name: LABEL });
    } catch (e) {
      if (e.status !== 404) throw e; // another run removed it first
    }
  };

  if (approved && !has) {
    await github.rest.issues.addLabels({ owner, repo, issue_number: number, labels: [LABEL] });
    // A push between the first read and addLabels finds no label to remove.
    // Check the head again: a later push sees the label and reconciles it.
    const { data: now } = await github.rest.pulls.get({ owner, repo, pull_number: number });
    if (now.head.sha !== head) {
      core.info(`Head moved ${head} -> ${now.head.sha}, approval is stale`);
      await remove();
      return false;
    }
    await github.rest.issues.createComment({ owner, repo, issue_number: number, body: COMMENT });
  } else if (!approved && has) {
    await remove();
  }
  if (approved) {
    for (const name of REVIEW_LABELS) {
      if (!labels.some(l => l.name === name)) continue;
      try {
        await github.rest.issues.removeLabel({ owner, repo, issue_number: number, name });
        core.info(`Removed label "${name}"`);
      } catch (e) {
        if (e.status !== 404) throw e;
      }
    }
  }
  return approved;
}

module.exports = { syncOne };
