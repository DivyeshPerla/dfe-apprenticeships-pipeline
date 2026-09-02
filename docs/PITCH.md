# Case study pitch — spoken script

**Full script runs ~10 minutes** at a realistic presenting pace (120 wpm —
slower than reading pace, because you will pause on the slides).

| target | what to cut |
|---|---|
| **10 min** | deliver as written |
| **8 min** | cut §7 (what the data showed) and the second half of §6 (the analysis-SQL repeat) |
| **5 min** | keep §1, §3, §6 (the bug) and §8 only — the hook, the problems, the bug, the close |

**If you cut to five, keep the bug story.** It is the only part that cannot be
inferred from the slides, and it is what makes the test suite look load-bearing
rather than decorative.

Written to be **spoken**, not read off a slide. Stage directions in brackets.

---

## 1 · Open — the hook · ~45 sec

> [Slide 1. Don't introduce yourself yet. Let the number sit there.]

"I want to start with a number.

Twenty-four times.

That's how wrong you get if you write the obvious query against the dataset I
picked for this project. Not twenty-four percent — twenty-four **times**.

And the query doesn't fail. It doesn't warn you. It runs in about a second and
gives you a number that looks completely plausible.

So that's what this is about. I picked a public dataset at random, found that it
was wrong in four different ways, and built a pipeline on Google Cloud that
doesn't repeat any of them."

---

## 2 · Why this dataset · ~60 sec

> [Slide 2.]

"Quick word on the dataset, because it matters less than you'd think.

It's UK government apprenticeship statistics. Free API, no key, seventeen tidy
columns, about fifty thousand rows. On paper it's an afternoon's work.

I want to be upfront: **I chose it more or less at random.** You don't need to
know anything about apprenticeships to follow this, and I'm not going to pretend
I had some deep domain thesis going in.

What I did have was a rule: profile the data before writing any pipeline code.

And that's the whole reason this project is interesting. Because when I actually
looked at it — properly, before building anything — it turned out to be hostile
in four separate ways. None of them show up in the schema. None of them throw an
error. Every one of them silently corrupts your answer.

That's not unusual. That's what most real source data looks like."

---

## 3 · The problem statement · ~90 sec

> [Slide 3, then 4. Slow down here — this is the foundation.]

"So, the four problems.

**First — and this is the twenty-four times.** Four fifths of the rows in this
dataset aren't data. They're subtotals. The publisher ships every level of
aggregation mixed in with the detail, in the same table, with no flag telling you
which is which. So when you sum the column, you're counting the same
apprenticeships once for every subtotal they happen to appear in.

The true answer for England in 2024/25 is about 353,500 starts. The obvious query
says 8.5 million. That's more apprenticeships than the working population of
Birmingham, Manchester and Leeds combined — and nothing anywhere tells you it's
wrong.

**Second — the numbers aren't numbers.** Up to a quarter of the values are
withheld for privacy, and they're encoded as *text* inside the numeric columns.
Little strings like 'low' or 'c'. So if you cast the column to an integer, a
quarter of your data silently disappears. And if you do the instinctive thing and
fill the nulls with zero — you've just invented data that says activity was zero
when actually it was hidden.

**Third — history gets rewritten.** There have been six versions of this dataset
published. Each one quietly restates figures in the previous one. Thousands of
them. So any analysis pinned to a single download is wrong the moment the next
version lands, and nothing tells you that either.

**Fourth — everything's rounded to the nearest ten.** Every single published
figure. Which means the parts can never exactly equal the whole, and any
reconciliation check you write on an equality will fail forever."

---

## 4 · Architecture · ~75 sec

> [Slide 5.]

"So here's what I built.

It's on Google Cloud, and it's deliberately simple. A scheduler wakes up a
workflow. The workflow runs a small job that asks the source one question: has
anything actually changed? If nothing has, it stops — costs one API call, takes
about thirty seconds. If something has, it extracts the new data, lands it in
Cloud Storage, and runs the transforms.

Two design decisions worth calling out.

**The raw layer is append-only and never modified.** Everything downstream is
rebuilt from it. That means I can reproduce any past state exactly — which turns
out to be the only reason the version-history analysis is possible at all.

**And I deliberately didn't use Airflow.** It's the conventional answer, and it's
the one that looks good on a CV. But it has no free tier — it'd cost two hundred
and fifty to four hundred pounds a month — and this source publishes four times a
year. Cloud Workflows does the same branching for effectively nothing. Choosing
the cheaper correct tool over the more impressive one was the right call, and
I'd rather defend that than pad the stack.

All of it is Terraform. Fifty-one resources. Nothing was clicked together in a
console, and the whole thing rebuilds from scratch in about four minutes."

---

## 5 · Key transformations · ~90 sec

> [Slide 6. This is the technical heart — don't rush it.]

"The transformations are where the four problems get solved.

**For the subtotals**, every row gets tagged with how aggregated it is — zero
means true detail, five means grand total. And then the published views are
pre-filtered. That's the important bit: a consumer of this warehouse *cannot*
reproduce the twenty-four-times error by accident, because the guardrail lives in
the model, not in the analyst remembering to add a WHERE clause.

**For the withheld values**, every measure splits into two columns: the number,
and a status explaining why it's missing. So a suppressed figure is null *with a
reason* — never zero. That distinction sounds pedantic until you realise
zero-filling would understate every regional total in the warehouse.

**For the rewritten history**, the fact table is slowly-changing — type two.
Every version is retained as a validity interval, so the warehouse can answer
'what did they report in January?' not just 'what do they say now.'

And there's a trap inside that one. When you compare versions to detect changes,
you have to compare **typed values, not the raw text.** Because one release
reformatted about four thousand two hundred values — changed '4' to '4.0'. Same
number, different string. If you diff on text, you open four thousand phantom
history records that represent nothing. I measured it: 73,797 records the naive
way, 69,589 done properly.

**And for the rounding** — the reconciliation test uses a tolerance derived from
the rounding regime itself, not a fudge factor I picked to make the test pass."

---

## 6 · Challenges and resolution · ~2 min

> [Slide 8 — the bug. This is the strongest thing you'll say. Slow right down.]

"Now — the part I actually want to talk about.

Twenty-six automated tests run on every single pipeline run. And one of them
earned its place while I was building this.

I'd made an unrelated change — tightening up some permissions — and I re-ran the
pipeline just to confirm nothing had broken. **And a test failed.** Not on
permissions. A uniqueness test.

Here's what happened. The calendar date had rolled over between two runs. And
because my raw layer is append-only — never overwrites — re-extracting the same
source version landed a *second* copy under a new date. And the table reads every
partition. So every single figure was being counted twice.

The test caught it and **stopped the run before any of it reached the published
layer.**

That's a bug that only appears when a date changes. It would have silently
doubled every number in the warehouse. And I found it in production, on its first
real occurrence, because the safety net was there.

There's a second half to that story. When I went to re-verify the headline
figures afterwards, I found the *same* bug in my analysis query. And I only found
it because I re-checked the absolute numbers — the twenty-four-times *ratio* still
looked correct, so if I'd only sanity-checked the story, I'd have missed it.

> [Slide 9 — compliance.]

"The same pattern applies to compliance. Rather than writing a policy document, I
wrote a script that checks eighteen controls against the live cloud environment
and fails the build if any of them regress.

It found two real things. **Data was leaving the country** — the build tool
silently stages source files in a US region, against a UK-only requirement, and
that had happened nine times before I caught it. And **an over-privileged default
account** that the build was quietly relying on.

The second one's the better story, because the obvious fix — just revoke the
permission — would have broken the pipeline. Knowing *why* the easy fix is wrong
is worth more than reporting a clean pass."

---

## 7 · What the data showed *[optional — cut this first]* · ~50 sec

> [Slide 11.]

"Once the data could be trusted, one finding fell out that I think matters
commercially.

The market didn't shrink. It moved upmarket.

Total volumes are basically flat across eight years. But the composition
completely inverted — entry-level provision went from forty-three percent down to
seventeen, and higher-level went from thirteen up to forty-one. They're about to
cross.

Anyone watching headline volumes alone would conclude this market is flat and
stable. It isn't. Demand didn't fall — it changed level. And that's invisible
until you can trust the data at detail grain, which is the entire argument for
building the pipeline properly."

---

## 8 · Close · ~30 sec

> [Final slide.]

"So — fifty-one resources, all as code. Twenty-six tests gating every publish.
Eighteen compliance checks against live infrastructure. Four machine learning
models. Zero pounds a month.

But the thing I'd want you to take away isn't the tooling. Anyone can wire cloud
services together.

The value was noticing the data was lying in four different ways — before writing
any code — and building something that doesn't repeat the lie.

Happy to go deeper on any part of it."

---

## Anticipated questions

**"Why not Airflow / Composer?"**
No free tier, ~£250–400/month, for a source that publishes quarterly. Cloud
Workflows expresses the same branch for effectively nothing. I'd use Composer the
moment there were enough DAGs to justify it.

**"Is it really free?"**
Measured usage sits inside the always-free tier for every service. Be precise:
the current bill is zero **on a trial account** — those are two different claims
and only the first is an argument.

**"How do you know the suppression codes mean what you say?"**
I don't, fully. I inferred them from the data's behaviour, tried four routes to
confirm against DfE documentation, and all four failed — the definitions sit in a
PDF outside the API. It's documented as an open question. **No number depends on
it** — it would mislabel a category, not corrupt a figure.

**"What would you do differently?"**
Confirm those codes on day one. Add CI at the start rather than near the end. And
if I could get learner-level data, most of the analytical limitations disappear —
at the cost of a real GDPR scope this project deliberately doesn't have.

**"How much of this was AI-assisted?"**
Be straight about it. The judgement calls — profiling first, rejecting Composer,
the tolerance test, splitting suppression from value — are the defensible part,
and you can explain every one.
