import ArgumentParser
import Foundation

enum Shell: String, ExpressibleByArgument, CaseIterable {
    case zsh
    case bash
    case fish
}

struct Completions: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completions",
        abstract: "Generate shell completion scripts"
    )

    @Argument(help: "Shell to generate completions for (zsh, bash, fish)")
    var shell: Shell

    mutating func run() throws {
        print(completionScript(for: shell))
    }

    private func completionScript(for shell: Shell) -> String {
        switch shell {
        case .zsh:
            Self.zshCompletion
        case .bash:
            Self.bashCompletion
        case .fish:
            Self.fishCompletion
        }
    }
}

// MARK: - Embedded completion scripts

extension Completions {
    // Shell scripts embedded as multiline string literals cannot be reflowed.
    // Alternatives considered: (1) load from bundled resource files at runtime — adds
    // file system dependency, breaks binary-only distribution; (2) break strings with
    // concatenation — destroys readability; (3) raise line_length project-wide — forbidden.
    // swiftlint:disable line_length
    static let zshCompletion = """
    #compdef dug

    # Completion script for dug - macOS-native DNS lookup utility
    # Install: copy to a directory in your $fpath (e.g. /usr/local/share/zsh/site-functions/)

    local -a plus_flags minus_flags record_types dns_classes

    record_types=(
      A AAAA ANY CAA CNAME DS DNSKEY HTTPS MX NAPTR NS NSEC
      PTR RRSIG SOA SRV SSHFP SVCB TXT
    )

    dns_classes=(IN CH HS)

    plus_flags=(
      '+short:show only rdata'
      '+traditional:dig-compatible output'
      '+pretty:ANSI-styled output'
      '+json:JSON structured output'
      '+yaml:YAML structured output'
      '+human:human-readable TTLs'
      '+resolve:reverse PTR annotation for A/AAAA'
      '+comments:show comment lines'
      '+question:show question section'
      '+answer:show answer section'
      '+authority:show authority section'
      '+additional:show additional section'
      '+stats:show statistics'
      '+cmd:show command line'
      '+all:set all display flags'
      '+tcp:use TCP instead of UDP'
      '+vc:use TCP (alias for +tcp)'
      '+dnssec:request DNSSEC records'
      '+do:set DNSSEC OK flag (alias for +dnssec)'
      '+cd:set checking disabled flag'
      '+adflag:set authenticated data flag'
      '+recurse:set recursion desired flag'
      '+rec:set recursion desired flag (alias)'
      '+search:use search list'
      '+tls:use DNS over TLS'
      '+tls-ca:verify TLS certificate'
      '+https:use DNS over HTTPS'
      '+https-get:use DNS over HTTPS with GET method'
      '+validate:probe DNSSEC validation'
      '+why:show resolver selection reason'
      '+time:set query timeout in seconds'
      '+tries:set number of query attempts'
      '+retry:set number of retries'
      '+tls-hostname:set TLS hostname for verification'
    )

    _dug() {
      local curcontext="$curcontext" state
      local -a args

      # Handle current word prefix
      if [[ -prefix + ]]; then
        # Complete +flag and +noflag options
        local -a all_plus_flags
        local flag desc
        for entry in "${plus_flags[@]}"; do
          flag="${entry%%:*}"
          desc="${entry#*:}"
          all_plus_flags+=("${flag}:${desc}")
          # Add +no variant
          local noflag="+no${flag#+}"
          all_plus_flags+=("${noflag}:disable ${desc}")
        done
        _describe -t plus-flags 'dug flag' all_plus_flags -P '+'
        return
      fi

      if [[ -prefix @ ]]; then
        # Complete @server with hostnames
        compset -P @
        _hosts
        return
      fi

      if [[ -prefix - ]]; then
        minus_flags=(
          '-x[reverse lookup]:IP address:'
          '-t[query type]:record type:('"${record_types[*]}"')'
          '-c[query class]:DNS class:('"${dns_classes[*]}"')'
          '-q[query name]:hostname:_hosts'
          '-p[server port]:port:'
          '-4[use IPv4 only]'
          '-6[use IPv6 only]'
        )
        _arguments -s : "${minus_flags[@]}"
        return
      fi

      # Default: complete hostnames and record types
      local -a completions
      for rt in "${record_types[@]}"; do
        completions+=("${rt}:DNS record type")
      done
      _describe -t record-types 'record type' completions
      _hosts
    }

    if [[ "${funcstack[1]}" = _dug ]]; then
        _dug "${@}"
    else
        compdef _dug dug
    fi
    """

    static let bashCompletion = """
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
        COMPREPLY=($(printf "@%s\\n" ${hosts}))
        return
      fi

      # Default: record types and hostnames
      COMPREPLY=($(compgen -W "${record_types}" -- "${cur}"))
      COMPREPLY+=($(compgen -A hostname -- "${cur}"))
    }

    complete -F _dug dug
    """

    static let fishCompletion = """
    # Fish completion for dug - macOS-native DNS lookup utility
    # Install: copy to /usr/local/share/fish/vendor_completions.d/

    # Disable file completions by default
    complete -c dug -f

    # Record types
    set -l record_types A AAAA ANY CAA CNAME DS DNSKEY HTTPS MX NAPTR NS NSEC PTR RRSIG SOA SRV SSHFP SVCB TXT

    # Record type completions
    for rt in $record_types
        complete -c dug -a $rt -d "DNS record type"
    end

    # Dash flags
    complete -c dug -s x -d "Reverse lookup" -r
    complete -c dug -s t -d "Query type" -r -a "(echo A AAAA ANY CAA CNAME DS DNSKEY HTTPS MX NAPTR NS NSEC PTR RRSIG SOA SRV SSHFP SVCB TXT | tr ' ' '\\n')"
    complete -c dug -s c -d "Query class" -r -a "IN CH HS"
    complete -c dug -s q -d "Query name" -r
    complete -c dug -s p -d "Server port" -r
    complete -c dug -s 4 -d "Use IPv4 only"
    complete -c dug -s 6 -d "Use IPv6 only"

    # Output format flags
    complete -c dug -a "+short" -d "Show only rdata"
    complete -c dug -a "+noshort" -d "Disable short output"
    complete -c dug -a "+traditional" -d "dig-compatible output"
    complete -c dug -a "+notraditional" -d "Disable traditional output"
    complete -c dug -a "+pretty" -d "ANSI-styled output"
    complete -c dug -a "+nopretty" -d "Disable pretty output"
    complete -c dug -a "+json" -d "JSON structured output"
    complete -c dug -a "+nojson" -d "Disable JSON output"
    complete -c dug -a "+yaml" -d "YAML structured output"
    complete -c dug -a "+noyaml" -d "Disable YAML output"
    complete -c dug -a "+human" -d "Human-readable TTLs"
    complete -c dug -a "+nohuman" -d "Disable human TTLs"
    complete -c dug -a "+resolve" -d "Reverse PTR annotation for A/AAAA"
    complete -c dug -a "+noresolve" -d "Disable PTR annotation"

    # Section display flags
    complete -c dug -a "+comments" -d "Show comment lines"
    complete -c dug -a "+nocomments" -d "Hide comment lines"
    complete -c dug -a "+question" -d "Show question section"
    complete -c dug -a "+noquestion" -d "Hide question section"
    complete -c dug -a "+answer" -d "Show answer section"
    complete -c dug -a "+noanswer" -d "Hide answer section"
    complete -c dug -a "+authority" -d "Show authority section"
    complete -c dug -a "+noauthority" -d "Hide authority section"
    complete -c dug -a "+additional" -d "Show additional section"
    complete -c dug -a "+noadditional" -d "Hide additional section"
    complete -c dug -a "+stats" -d "Show statistics"
    complete -c dug -a "+nostats" -d "Hide statistics"
    complete -c dug -a "+cmd" -d "Show command line"
    complete -c dug -a "+nocmd" -d "Hide command line"
    complete -c dug -a "+all" -d "Set all display flags"
    complete -c dug -a "+noall" -d "Clear all display flags"

    # Protocol flags
    complete -c dug -a "+tcp" -d "Use TCP instead of UDP"
    complete -c dug -a "+notcp" -d "Use UDP"
    complete -c dug -a "+vc" -d "Use TCP (alias)"
    complete -c dug -a "+novc" -d "Use UDP (alias)"
    complete -c dug -a "+dnssec" -d "Request DNSSEC records"
    complete -c dug -a "+nodnssec" -d "Disable DNSSEC"
    complete -c dug -a "+do" -d "Set DNSSEC OK flag"
    complete -c dug -a "+nodo" -d "Clear DNSSEC OK flag"
    complete -c dug -a "+cd" -d "Set checking disabled flag"
    complete -c dug -a "+nocd" -d "Clear checking disabled flag"
    complete -c dug -a "+adflag" -d "Set authenticated data flag"
    complete -c dug -a "+noadflag" -d "Clear authenticated data flag"
    complete -c dug -a "+recurse" -d "Set recursion desired"
    complete -c dug -a "+norecurse" -d "Disable recursion"
    complete -c dug -a "+rec" -d "Set recursion desired (alias)"
    complete -c dug -a "+norec" -d "Disable recursion (alias)"
    complete -c dug -a "+search" -d "Use search list"
    complete -c dug -a "+nosearch" -d "Disable search list"

    # Transport flags
    complete -c dug -a "+tls" -d "Use DNS over TLS"
    complete -c dug -a "+notls" -d "Disable DNS over TLS"
    complete -c dug -a "+tls-ca" -d "Verify TLS certificate"
    complete -c dug -a "+notls-ca" -d "Skip TLS verification"
    complete -c dug -a "+https" -d "Use DNS over HTTPS"
    complete -c dug -a "+nohttps" -d "Disable DNS over HTTPS"
    complete -c dug -a "+https-get" -d "Use DoH with GET method"
    complete -c dug -a "+nohttps-get" -d "Disable DoH GET method"
    complete -c dug -a "+validate" -d "Probe DNSSEC validation"
    complete -c dug -a "+novalidate" -d "Disable validation probe"

    # Debug flags
    complete -c dug -a "+why" -d "Show resolver selection reason"
    complete -c dug -a "+nowhy" -d "Hide resolver selection reason"

    # Value flags
    complete -c dug -a "+time=" -d "Query timeout in seconds"
    complete -c dug -a "+tries=" -d "Number of query attempts"
    complete -c dug -a "+retry=" -d "Number of retries"
    complete -c dug -a "+tls-hostname=" -d "TLS hostname for verification"
    """
    // swiftlint:enable line_length
}
