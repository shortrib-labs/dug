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
complete -c dug -s t -d "Query type" -r -a "(echo A AAAA ANY CAA CNAME DS DNSKEY HTTPS MX NAPTR NS NSEC PTR RRSIG SOA SRV SSHFP SVCB TXT | tr ' ' '\n')"
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
