#!/bin/bash
# Copyright (c) 2009 Sébastien Gross <seb•ɑƬ•chezwam•ɖɵʈ•org>
# Released under GPL, see http://gnu.org for further information.

# default options
debug=
config=config
ca_dir=ca
openssl=$(which openssl)
ca_conf=ca.conf
cn_conf=cn.conf
serial="../serial.txt"
dhparam_opt="2048"
genrsa_opt="-des3 2048"
passgen=$(which makepasswd)
if test -n "${passgen}"; then
    passgen=/usr/bin/makepasswd
    passgen_opt="-chars 10"
else
    passgen="${openssl}"
    # password length should be multiple of 3.
    passgen_opt="rand -base64 9"
fi
sed=$(which gsed)
if test -z "${sed}"; then
    sed=$(which sed)
fi
openvpn=$(which openvpn)
if test -z "${openvpn}"; then
    # TODO automaticaly detect openvpn binary on MacOSX
    openvpn="/Applications/Tunnelblick.app/Contents/Resources/openvpn/openvpn-2.2.1/openvpn"
fi


req_opt="-utf8 -days 180"
workdir=out
x509_opt="-days 180"
add_file="client-linux.ovpn client-mac.ovpn client-windows.ovpn"

function die() {
    echo "$@" >&2
    exit 1
}

function help {
    exit_code=${1:-1}
    cat <<EOF
Usage $0 [ options ] [ commands ] [ cmd options ] [ cmd args ]

options:

  -d|--debug              Display debug messages
  -h|--help               Display this help screen
  -w|--workdir DIR        Set the working directory (${workdir})
  -c|--config             Set configuration file (${config})
  --ca-dir                Set the CA directory (${ca_dir})
  --openssl PATH          Path to openssl binary (${openssl})
  --passgen PATH          Path to the password generator (${passgen})
  --passgen-opt OPT       Options for the password generator (${passgen_opt})
  --sed PATH              Path to sed (${sed})

Commands:

  ca                    Create a new CA
    --ca-conf PATH        Path to openssl configuration (${ca_conf})
    --dump                Dump CA
    --dump-crl            Dump CRL
    --no-pass             Create a key without password
    --pass PASS           Set the CA password
    --genrsa-opt OPT      Options for gensra (${genrsa_opt})
    --req-opt OPT         Options for req (${req_opt})

  cn                    Create a new certificate
    --add-file FILE       Add file to the certificate directory (${add_file})
    --cn-conf PATH        Path to openssl configuration (${cn_conf})
    --dump                Dump certificate
    --revoke              Revoke certificate
    --genrsa-opt OPT      Options for gensra (${genrsa_opt})
    --no-pass             Create a key without password
    --pass PASS           Set the certificate password
    --dhparam             Add Diffie Hillman parameters
    --dhparam-opt OPT     Options for dhparam (${dhparam_opt})
    --x509-opt OPT        Options for x509 (${x509_opt})
    --serial FILE         Serial file (${serial})
    --copy-crl            Copy Certificate Revocation List
    cn                    Set the CN to the certificate

EOF
    exit ${exit_code}
}

function do_ca() {
    local pass=
    local no_pass=
    local dump=
    local dump_crl=
    while test $# -ne 0; do
	case "$1" in
	    --ca-conf)
		test -z "$2" && die "$1 requires a parameter"
		ca_conf="$2"
		shift ;;
	    --dump) dump=1;;
	    --dump-crl) dump_crl=1;;
	    --genrsa-opt)
		test -z "$2" && die "$1 requires a parameter"
		genrsa_opt="$2"
		shift ;;
	    --no-pass) no_pass=1;;
	    --pass)
		test -z "$2" && die "$1 requires a parameter"
		pass="$2"
		shift ;;
	    --req-opt)
		test -z "$2" && die "$1 requires a parameter"
		req_opt="$2"
		shift ;;
	    --) shift ; break ;;
	    -*|*) help 0 ;;
	esac
	shift
    done
    if ! test -z "${dump}"; then
	${openssl} x509 -text -in "${ca_dir}/ca.pem"
	return
    fi
    if ! test -z "${dump_crl}"; then
	${openssl} crl -text -in "${ca_dir}/crl.pem"
	cat "${ca_dir}/index.txt"
	return
    fi
    test -z "${pass}" && pass=$(${passgen} ${passgen_opt})
    test -d "${ca_dir}" || mkdir -p "${ca_dir}"
    cd "${ca_dir}"
    echo "${pass}" > ca.pass
    ${openssl} genrsa -passout pass:${pass} -out ca.key ${genrsa_opt}
    ${openssl} rsa -passin pass:${pass} -in ca.key -out ca.key-nopass
    ${openssl} req -new -x509 -key ca.key-nopass -out ca.pem \
	-config "${ORIGIN}/${ca_conf}" ${req_opt}

    touch index.txt
    touch index.txt.attr
    printf '%.6d' 0 > number.txt
    # Generate CRL
    ${openssl} ca -config "${ORIGIN}/${ca_conf}" -gencrl \
	-keyfile ca.key-nopass -cert ca.pem -out crl.pem
    openssl crl -inform PEM -in crl.pem -outform DER \
	-out crl.der


    test -z "${no_pass}" && rm -f ca.key-nopass

} 


function do_cn() {
    local pass=
    local no_pass=
    local dump=
    local revoke=
    local cn=
    local dhparam=
    local copy_crl=
    local tls_auth=
    local gen_tls=
    while test $# -ne 0 && test -z "${cn}"; do
	case "$1" in
	    --add-file)
	        # Can be empty
		add_file="$2"
		shift ;;
	    --cn-conf)
		test -z "$2" && die "$1 requires a parameter"
		cn_conf="$2"
		shift ;;
	    --dhparam) dhparam=1 ;;
	    --dhparam-opt)
		test -z "$2" && die "$1 requires a parameter"
		dhparam_opt="$2"
		shift ;;
	    --dump) dump=1 ;;
	    --revoke) revoke=1;;
	    --genrsa-opt)
		test -z "$2" && die "$1 requires a parameter"
		genrsa_opt="$2"
		shift ;;
	    --no-pass) no_pass=1 ;;
	    --gen-tls) gen_tls=1 ;;
	    --tls-auth)
		test -z "$2" && die "$1 requires a parameter"
		tls_auth="$2"
		shift ;;
	    --pass)
		test -z "$2" && die "$1 requires a parameter"
		pass="$2"
		shift ;;
	    --x509-opt)
		test -z "$2" && die "$1 requires a parameter"
		x509_opt="$2"
		shift ;;
	    --copy-crl)
		copy_crl=1 ;;
	    --) shift ; break ;;
	    -*) help 0 ;;
	    *) cn="$1" ;;
	esac
	shift
    done
    test -z "${cn}" && die "No Common Name defined"
    if ! test -z "${dump}"; then
	${openssl} x509 -text -in "${cn}/${cn}.pem"
	return
    fi
    if ! test -z "${revoke}"; then
	cd "${ca_dir}"
	${openssl} ca -config "${ORIGIN}/${ca_conf}" \
	    -revoke "../${cn}/${cn}.pem" -keyfile ca.key-nopass \
	    -cert ca.pem
	${openssl} ca -config "${ORIGIN}/${ca_conf}" -gencrl \
	    -keyfile ca.key-nopass -cert ca.pem -out crl.pem
	${openssl} crl -inform PEM -in crl.pem -outform DER -out crl.der
	return
    fi

    test -z "${pass}" && pass=$(${passgen} ${passgen_opt})
    test -d "${cn}" || mkdir -p "${cn}"
    cp "${ORIGIN}/${cn_conf}" "${cn}/${cn}.conf"
    if ! test -z "${add_file}"; then
	for f in ${add_file}; do
	    ${sed} "s/@@CN@@/${cn}/g" < "${ORIGIN}/${f}" \
		> ${cn}/$(basename ${f})
	done
    fi
    cd "${cn}"
    ${sed} -i "s/@@CN@@/${cn}/g" "${cn}.conf"
    echo "${pass}" > ${cn}.pass

    # if ! test -f ${serial}; then
    #     serial_id=1
    # else
    # 	serial_id=$(expr `cat ${serial}` + 1)
    # fi
    # printf %.6d ${serial_id} > ${serial}

    if ! test -f ${serial}; then
	echo 00 > ${serial}
    fi


    local _ca_dir="${ORIGIN}/${workdir}/${ca_dir}"
    ${openssl} genrsa -passout pass:${pass} -out ${cn}.key ${genrsa_opt}
    ${openssl} rsa -passin pass:${pass} -in ${cn}.key -out ${cn}.key-nopass
    ${openssl} req -new -nodes -key ${cn}.key-nopass -out ${cn}.csr \
	-config "${cn}.conf"
    ${openssl} x509 -req -in ${cn}.csr -CA "${_ca_dir}/ca.pem" \
	-CAkey "${_ca_dir}/ca.key-nopass" -CAserial ${serial} \
	-out ${cn}.pem ${x509_opt}
    cp "${_ca_dir}/ca.pem" .
    test -z "${copy_crl}" || cp "${_ca_dir}/crl.pem" .
    test -z "${dhparam}" || ${openssl} dhparam -out dh2048.pem ${dhparam_opt}
    if test -n "${gen_tls}"; then
	${openvpn} --genkey --secret tls-auth.key
	tls_auth="${cn}"
    fi
    if test -z "${debug}"; then
	rm -f "${cn}.conf" "${cn}.csr"
    fi
    if test -z "${no_pass}"; then
	rm -f "${cn}.key-nopass"
    else
	rm -f "${cn}.key" "${cn}.pass"
	mv "${cn}.key-nopass" "${cn}.key"
    fi
}


if test -e "${config}"; then
    . "${config}"
fi


# parse command line options
command=
while test $# != 0 && test -z "$command"; do
    case $1 in
	ca|cn) command=do_$1;;
	--ca-dir)
	    test -z "$2" && die "$1 requires a parameter"
	    ca_dir="$2"
	    shift ;;
	--genrsa-opt)
	    test -z "$2" && die "$1 requires a parameter"
	    gen_rsa="$2"
	    shift ;;
	--passgen)
	    test -z "$2" && die "$1 requires a parameter"
	    passgen="$2"
	    shift ;;
	--passgen-opt)
	    test -z "$2" && die "$1 requires a parameter"
	    passgen_opt="$2"
	    shift ;;
	--openssl)
	    test -z "$2" && die "$1 requires a parameter"
	    openssl="$2"
	    shift ;;
	--sed)
	    test -z "$2" && die "$1 requires a parameter"
	    sed="$2"
	    shift ;;
	-w|--workdir)
	    test -z "$2" && die "$1 requires a parameter"
	    workdir="$2"
	    shift ;;
	-c|--config)
	    test -z "$2" && die "$1 requires a parameter"
	    config="$2"
	    shift ;;
	-d|--debug) debug=1 ;;
	--help|-h) help 0;;
	--) shift ; break ;;
	-*|*) help 1 ;;
    esac
    shift
done

if test -e "${config}"; then
    . "${config}"
fi

test -z "${command}" && die "No command specified"
ORIGIN=$(pwd)
# move to the working directory
test -d "${workdir}" || mkdir -p "${workdir}"
cd "${workdir}"
"${command}" "$@"
