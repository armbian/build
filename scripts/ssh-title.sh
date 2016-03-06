if [ -n "$PS1" ] && ( [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ] ); then
 tput tsl > /dev/null
 if [ "$?" -eq 0 ]; then
  echo `tput tsl` `whoami`@`hostname` `tput fsl`
 fi
fi