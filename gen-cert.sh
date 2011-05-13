#!/bin/sh
# Copyright (c) 2009 Sébastien Gross <seb•ɑƬ•chezwam•ɖɵʈ•org>
# Released under GPL, see http://gnu.org for further information.

# default options
ca_dir=ca
openssl=/usr/bin/openssl
ca_conf=ca.conf
cn_conf=cn.conf
dhparam_opt="2048"
genrsa_opt="-des3 2048"
passgen=/usr/bin/makepasswd
passgen_opt="-chars 10"
req_opt="-utf8 -days 180"
workdir=out
x509_opt="-days 180"


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
  --ca-dir                Set the CA directory (${ca_dir})
  --openssl PATH          Path to openssl binary (${openssl})
  --passgen PATH          Path to the password generator (${passgen})
  --passgen-opt OPT       Options for the password generator (${passgen_opt})

Commands:

  ca                    Create a new CA
    --ca-conf PATH        Path to openssl configuration (${ca_conf})
    --dump                Dump CA
    --no-pass             Create a key without password
    --pass PASS           Set the CA password
    --genrsa-opt OPT      Options for gensra (${gensra_opt})
    --req-opt OPT         Options for req (${req_opt})

  cn                    Create a new certificate
    --add-file FILE       Add file to the certificate directory
    --cn-conf PATH        Path to openssl configuration (${cn_conf})
    --dump                Dump certificate
    --genrsa-opt OPT      Options for gensra (${gensra_opt})
    --no-pass             Create a key without password
    --pass PASS           Set the certificate password
    --dhparam             Add Diffie Hillman parameters
    --dhparam-opt OPT     Options for dhparam (${dhparam_opt})
    --x509-opt OPT        Options for x509 (${x509_opt})
    cn                    Set the CN to the certificate

EOF
  exit ${exit_code}
}

function do_ca() {
  local pass=
  local no_pass=
  local dump=
  while test $# -ne 0; do
    case "$1" in
      --ca-conf)
        test -z "$2" && die "$1 requires a parameter"
        ca_conf="$2"
        shift ;;
      --dump) dump=1;;
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
  test -z "${pass}" && pass=$(${passgen} ${passgen_opt})
  test -d "${ca_dir}" || mkdir -p "${ca_dir}"
  cd "${ca_dir}"
  echo "${pass}" > ca.pass
  ${openssl} genrsa -passout pass:${pass} -out ca.key ${genrsa_opt}
  ${openssl} rsa -passin pass:${pass} -in ca.key -out ca.key-nopass
  ${openssl} req -new -x509 -key ca.key-nopass -out ca.pem \
    -config "${ORIGIN}/${ca_conf}" ${req_opt}
  test -z "${no_pass}" && rm -f ca.key-nopass
} 


function do_cn() {
  local pass=
  local no_pass=
  local dump=
  local cn=
  local dhparam=
  local add_file=
  while test $# -ne 0 && test -z "${cn}"; do
    case "$1" in
      --add-file)
        test -z "$2" && die "$1 requires a parameter"
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
      --genrsa-opt)
        test -z "$2" && die "$1 requires a parameter"
        genrsa_opt="$2"
        shift ;;
      --no-pass) no_pass=1 ;;
      --pass)
        test -z "$2" && die "$1 requires a parameter"
        pass="$2"
        shift ;;
      --x509-opt)
        test -z "$2" && die "$1 requires a parameter"
        x509_opt="$2"
        shift ;;
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
  test -z "${pass}" && pass=$(${passgen} ${passgen_opt})
  test -d "${cn}" || mkdir -p "${cn}"
  cp "${ORIGIN}/${cn_conf}" "${cn}/${cn}.conf"
  if ! test -z "${add_file}"; then
    sed "s/@@CN@@/${cn}/g" < "${ORIGIN}/${add_file}" \
      > ${cn}/$(basename ${add_file})
  fi
  cd "${cn}"
  sed -i "s/@@CN@@/${cn}/g" "${cn}.conf"
  echo "${pass}" > ${cn}.pass
  echo 01 > serial.txt
  local _ca_dir="${ORIGIN}/${workdir}/${ca_dir}"
  ${openssl} genrsa -passout pass:${pass} -out ${cn}.key ${genrsa_opt}
  ${openssl} rsa -passin pass:${pass} -in ${cn}.key -out ${cn}.key-nopass
  ${openssl} req -new -nodes -key ${cn}.key-nopass -out ${cn}.csr \
    -config "${cn}.conf"
  ${openssl} x509 -req -in ${cn}.csr -CA "${_ca_dir}/ca.pem" \
    -CAkey "${_ca_dir}/ca.key-nopass" -CAserial serial.txt \
    -out ${cn}.pem ${x509_opt}
  cp "${_ca_dir}/ca.pem" .
  test -z "${dhparam}" || ${openssl} dhparam -out dh2048.pem ${dhparam_opt}
  #rm -f serial.txt "${cn}.conf" "${cn}.csr"
  if test -z "${no_pass}"; then
    rm -f "${cn}.key-nopass"
  else
    rm -f "${cn}.key" "${cn}.pass"
    mv "${cn}.key-nopass" "${cn}.key"
  fi
}

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
    --workdir)
      test -z "$2" && die "$1 requires a parameter"
      workdir="$2"
      shift ;;
    --help|-h) help 0;;
    --) shift ; break ;;
    -*|*) help 1 ;;
  esac
  shift
done

test -z "${command}" && die "No command specified"
ORIGIN=$(pwd)
# move to the working directory
test -d "${workdir}" || mkdir -p "${workdir}"
cd "${workdir}"
"${command}" "$@"


# vim:tw=78:ts=2:sts=2:sw=2:syntax=sh:set et:
