# shellcheck shell=sh
# Login shells start from the default PATH in /etc/profile and would otherwise
# drop the agent tools that the container environment puts first.
case ":${PATH}:" in
  *:/opt/agent-tools:*) ;;
  *) PATH="/opt/agent-tools:${PATH}" ;;
esac
export PATH
