Test that installed binaries are visible in dependent packages

  $ . ./helpers.sh

  $ mkdir dune.lock
  $ cat >dune.lock/lock.dune <<EOF
  > (lang package 0.1)
  > EOF
  $ cat >dune.lock/test.pkg <<EOF
  > (build
  >  (system "\| echo "#!/bin/sh\necho from test package" > foo;
  >          "\| chmod +x foo;
  >          "\| touch libxxx lib_rootxxx;
  >          "\| cat >test.install <<EOF
  >          "\| bin: [ "foo" ]
  >          "\| lib: [ "libxxx" ]
  >          "\| lib_root: [ "lib_rootxxx" ]
  >          "\| share_root: [ "lib_rootxxx" ]
  >          "\| EOF
  >  ))
  > EOF

  $ cat >dune.lock/usetest.pkg <<EOF
  > (deps test)
  > (build
  >  (progn
  >   (run foo)
  >   (run mkdir -p %{prefix})))
  > EOF

  $ build_pkg usetest
  from test package

  $ show_pkg_targets test
  
  /bin
  /bin/foo
  /cookie
  /lib
  /lib/lib_rootxxx
  /lib/test
  /lib/test/libxxx
  /share
  /share/lib_rootxxx
  $ show_pkg_cookie test
  { files =
      map
        { LIB : [ In_build_dir "default/.pkg/test/target/lib/test/libxxx" ]
        ; LIB_ROOT :
            [ In_build_dir "default/.pkg/test/target/lib/lib_rootxxx" ]
        ; BIN : [ In_build_dir "default/.pkg/test/target/bin/foo" ]
        ; SHARE_ROOT :
            [ In_build_dir "default/.pkg/test/target/share/lib_rootxxx" ]
        }
  ; variables = []
  }

It should also be visible in the workspace:

  $ cat >dune-project <<EOF
  > (lang dune 3.9)
  > EOF

  $ cat >dune <<EOF
  > (rule
  >  (with-stdout-to testout (run %{bin:foo})))
  > EOF

  $ dune build ./testout && cat _build/default/testout
  File "dune", line 2, characters 30-40:
  2 |  (with-stdout-to testout (run %{bin:foo})))
                                    ^^^^^^^^^^
  Error: Program foo not found in the tree or in PATH
   (context: default)
  [1]
