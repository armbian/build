// Shared logic for the "Work in progress" label automation.
//
// A pull request is "work in progress" when a reviewer has requested changes
// OR any review conversation is still unresolved. The label is recomputed from
// the PR's live state, so it is idempotent and the same regardless of what
// triggered the run.
//
// Used by:
//   - maintenance-label-wip.yml   (workflow_run worker: instant, one PR)
//   - maintenance-label-wip-sweep.yml (cron backstop: all open PRs)
//
// These run from the default branch context (workflow_run / schedule), which
// has a read/write GITHUB_TOKEN even for fork PRs -- unlike a pull_request_review
// trigger, whose token is read-only on forks.

const LABEL = "Work in progress";

// Returns { wip, reviewDecision, unresolved } for a single PR.
async function evaluate(github, owner, repo, number) {
  let reviewDecision = null;
  let unresolved = 0;
  let after = null;

  do {
    const query = `
      query($owner:String!, $repo:String!, $number:Int!, $after:String) {
        repository(owner:$owner, name:$repo) {
          pullRequest(number:$number) {
            reviewDecision
            reviewThreads(first:100, after:$after) {
              nodes { isResolved }
              pageInfo { hasNextPage endCursor }
            }
          }
        }
      }`;
    const data = await github.graphql(query, { owner, repo, number, after });
    const pr = data.repository.pullRequest;
    reviewDecision = pr.reviewDecision;
    for (const t of pr.reviewThreads.nodes) {
      if (!t.isResolved) unresolved++;
    }
    after = pr.reviewThreads.pageInfo.hasNextPage
      ? pr.reviewThreads.pageInfo.endCursor
      : null;
  } while (after);

  return { wip: reviewDecision === "CHANGES_REQUESTED" || unresolved > 0, reviewDecision, unresolved };
}

// Add or remove the label on one PR to match its evaluated state.
async function syncOne({ github, core, owner, repo, number }) {
  const { wip, reviewDecision, unresolved } = await evaluate(github, owner, repo, number);

  const current = await github.rest.issues.listLabelsOnIssue({
    owner, repo, issue_number: number, per_page: 100,
  });
  const has = current.data.some(l => l.name === LABEL);
  const state = `reviewDecision=${reviewDecision} unresolved=${unresolved}`;

  if (wip && !has) {
    await github.rest.issues.addLabels({ owner, repo, issue_number: number, labels: [LABEL] });
    core.info(`PR #${number}: added "${LABEL}" (${state})`);
  } else if (!wip && has) {
    await github.rest.issues.removeLabel({ owner, repo, issue_number: number, name: LABEL });
    core.info(`PR #${number}: removed "${LABEL}" (${state})`);
  } else {
    core.info(`PR #${number}: no change, has=${has} (${state})`);
  }
}

// Sweep every open PR (paginated). One PR failing does not abort the rest.
async function syncAllOpen({ github, core, owner, repo }) {
  let after = null;
  let count = 0;

  do {
    const query = `
      query($owner:String!, $repo:String!, $after:String) {
        repository(owner:$owner, name:$repo) {
          pullRequests(states: OPEN, first: 50, after: $after) {
            nodes { number }
            pageInfo { hasNextPage endCursor }
          }
        }
      }`;
    const data = await github.graphql(query, { owner, repo, after });
    const conn = data.repository.pullRequests;
    for (const pr of conn.nodes) {
      count++;
      try {
        await syncOne({ github, core, owner, repo, number: pr.number });
      } catch (e) {
        core.warning(`PR #${pr.number}: sync failed: ${e.message}`);
      }
    }
    after = conn.pageInfo.hasNextPage ? conn.pageInfo.endCursor : null;
  } while (after);

  core.info(`Swept ${count} open PR(s).`);
}

module.exports = { syncOne, syncAllOpen };
