-- Configure /usr/bin/osascript and require one argument.
-- This example does not control other apps or need Automation consent.
on run argv
    return item 1 of argv
end run
