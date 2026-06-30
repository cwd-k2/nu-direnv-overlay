use std/assert

source $autoload
open $inherited_json | load-env
source $apply_a
assert equal ($env.PROJECT_ROOT? | default "") $project_dir "setup-like env did not load initially"

open $inherited_b_json | load-env
source $project_to_project
assert equal ($env.PROJECT_ROOT? | default "") "" "setup-like env leaked into project-b"

hide-env PROJECT_MARK --ignore-errors
hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
source $cleanup
assert equal ($env.PROJECT_ROOT? | default "") "" "setup-like env resurrected in unmanaged directory"

open $inherited_json | load-env
source $apply_again
assert equal ($env.PROJECT_ROOT? | default "") $project_dir "setup-like env did not restore after returning"
