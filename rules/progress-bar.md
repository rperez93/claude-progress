# progress-bar (managed by claude-progress install.sh)

`cc-progress` puts live progress bars — count, elapsed time, ETA — in the status line.

When the user asks for a progress bar, an ETA, "how many are left", or to be kept posted
on a countable job, load the `progress-bar` skill and use `cc-progress`; do not substitute
printed percentages or prose updates. Count the total first, make the update a side effect
of the work (`cc-progress tick` inside the loop, or `| cc-progress pipe`), and always end
with `cc-progress done` or `cc-progress fail`. Do not start a bar when none was asked for.
