# BASH or ZSH shell alieases
alias ll='ls -l'
alias la='ls -A'
alias l='ls -CF'
alias kernel="uname -r | sed 's/[1-9]\+[0-9]*\.[0-9]\+\.[0-9]\+-//' | sed 's/[1-9]\+[0-9]*\.[0-9]*\-rc[0-9]\+-//'"
alias showip='ip -4 addr show scope global | grep inet | awk "{print $2}" | cut -d"/" -f1 | sed "s/    inet //g" | paste -s -d, -'
