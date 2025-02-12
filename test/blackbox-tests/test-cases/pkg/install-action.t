Testing install actions

  $ . ./helpers.sh

  $ mkdir dune.lock
  $ cat >dune.lock/lock.dune <<EOF
  > (lang package 0.1)
  > EOF
  $ cat >dune.lock/test.pkg <<'EOF'
  > (install (system "echo foobar; mkdir -p %{lib}; touch %{lib}/xxx"))
  > EOF

  $ build_pkg test
  foobar

  $ export BUILD_PATH_PREFIX_MAP="/PKG_ROOT=test/target:$BUILD_PATH_PREFIX_MAP"

  $ show_pkg_targets test
  
  /bin
  /cookie
  /doc
  /doc/test
  /etc
  /etc/test
  /lib
  /lib/stublibs
  /lib/test
  /lib/toplevel
  /lib/xxx
  /man
  /sbin
  /share
  /share/test

  $ show_pkg_cookie test
  { files =
      map { LIB_ROOT : [ In_build_dir "default/.pkg/test/target/lib/xxx" ] }
  ; variables = []
  }
