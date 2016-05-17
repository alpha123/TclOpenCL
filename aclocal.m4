#
# Include the TEA standard macro set
#

builtin(include,tclconfig/tcl.m4)

#
# Add here whatever m4 macros you want to define for your package
#

builtin(include,m4/ax_pkg_swig.m4)
builtin(include,m4/acx_pthread.m4)
builtin(include,m4/ax_check_cl.m4)
