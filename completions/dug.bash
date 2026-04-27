# Bash completion for dug - macOS-native DNS lookup utility
# Install: copy to /usr/local/etc/bash_completion.d/ or source directly

_dug() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local record_types="A AAAA ANY CAA CNAME DS DNSKEY HTTPS MX NAPTR NS NSEC PTR RRSIG SOA SRV SSHFP SVCB TXT"
  local dns_classes="IN CH HS"

  local plus_flags="+short +noshort +traditional +notraditional +pretty +nopretty +json +nojson +yaml +noyaml +human +nohuman +resolve +noresolve +comments +nocomments +question +noquestion +answer +noanswer +authority +noauthority +additional +noadditional +stats +nostats +cmd +nocmd +all +noall +tcp +notcp +vc +novc +dnssec +nodnssec +do +nodo +cd +nocd +adflag +noadflag +recurse +norecurse +rec +norec +search +nosearch +tls +notls +tls-ca +notls-ca +https +nohttps +https-get +nohttps-get +validate +novalidate +why +nowhy +time +tries +retry +tls-hostname"

  # Complete arguments to -t and -c
  case "${prev}" in
    -t)
      COMPREPLY=($(compgen -W "${record_types}" -- "${cur}"))
      return
      ;;
    -c)
      COMPREPLY=($(compgen -W "${dns_classes}" -- "${cur}"))
      return
      ;;
    -p|-x|-q)
      # These take values but we can't complete them meaningfully
      return
      ;;
  esac

  # Complete +flags
  if [[ "${cur}" == +* ]]; then
    COMPREPLY=($(compgen -W "${plus_flags}" -- "${cur}"))
    return
  fi

  # Complete -flags
  if [[ "${cur}" == -* ]]; then
    COMPREPLY=($(compgen -W "-x -t -c -q -p -4 -6" -- "${cur}"))
    return
  fi

  # Complete @server with hostnames
  if [[ "${cur}" == @* ]]; then
    local prefix="${cur#@}"
    local hosts
    hosts=$(compgen -A hostname -- "${prefix}")
    COMPREPLY=($(printf "@%s\n" ${hosts}))
    return
  fi

  # Default: record types and hostnames
  COMPREPLY=($(compgen -W "${record_types}" -- "${cur}"))
  COMPREPLY+=($(compgen -A hostname -- "${cur}"))
}

complete -F _dug dug
