# General LLM instructions

Generated prose: keep very brief. Includes code comments, commit messages, pull request text, issue reports, patch cover letters. Reviewers read many. Walls of text waste their time.

State the goal and the expected result. Do not describe how: the code and the diff show that.
Issue reports: include the steps and logs needed to reproduce.
Pull request text: also state which boards were tested.

Clarity register: ASD-STE100 Simplified Technical English. Apply to all generated text:

- One idea per sentence. Max 20 words.
- Active voice. Present tense where true.
- Instructions in imperative: "Run X", not "X should be run".
- One term per concept. No synonym rotation.
- Noun clusters max 3 words.
- Pronoun only with one clear referent. Else repeat the noun.
- Cut fillers. Keep every word that removes ambiguity.
- Brevity conflicts with clarity → clarity wins.
