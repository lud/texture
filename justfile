
_mix_deps:
  mix deps.get

test:
  mix test

lint:
  mix compile --force --warnings-as-errors
  mix credo

dialyzer:
  mix dialyzer --format dialyzer

format:
  mix format --migrate

_libdev_check:
  mix libdev.check

_git_status:
  git status

docs:
  mix docs

changelog:
  git cliff -o CHANGELOG.md

readme:
  mix rdmx.update README.md

check: _mix_deps format _libdev_check readme _git_status
