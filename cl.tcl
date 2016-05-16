package provide TclOpenCL 0.1
package require vectcl

tclOpenCLInit 0

namespace eval ::TclOpenCL {
    namespace export Buffer Context CommandQueue platforms program Program

    proc capitalize {s} {
        string replace $s 0 0 [string toupper [string index $s 0]]
    }

    proc camelize {s} {
        subst [regsub -all -- {_(\w)} $s {[string toupper \1]}]
    }

    proc ::oo::define::lazy {family type name} {
        set clInfoType [set ::CL_[string toupper $family]_[string toupper $name]]
        set clInfoProc clGet[::TclOpenCL::capitalize $family]Info[::TclOpenCL::capitalize $type]
        set body [concat "{ my variable _$name; " if "{\[info exists _$name]} {
            set _$name
        }" else "{
            set query \[$clInfoProc \[set _ptr] $clInfoType]
            if {\[lindex \[set query] 0] != $::CL_SUCCESS} {
                return -code error {Could not query OpenCL device $name}
            }
            set _$name \[lindex \[set query] 1]
        } }"]
        uplevel 1 method [::TclOpenCL::camelize $name] "{}" $body
    }

    proc ::oo::define::refcounted {family} {
        set retain clRetain[::TclOpenCL::capitalize $family]
        set release clRelease[::TclOpenCL::capitalize $family]
        set destructor [concat "{ if {\[$release \[set _ptr]] != $::CL_SUCCESS} {
            return -code error {Could not release OpenCL $family}
        } }"]
        set cloned [concat "{ if {\[$retain \[set _ptr]] != $::CL_SUCCESS} {
            return -code error {Could not retain OpenCL $family}
        } }"]
        uplevel 1 destructor $destructor
        uplevel 1 method <cloned> "{_}" $cloned
    }

    oo::class create Device {
        variable _platform _ptr

        constructor {platform id} {
            set _platform $platform
            set _ptr $id
        }
        # Memory management is just for subdevices and has no effect if this is
        # a root-level device.
        refcounted device

        method platform {} {set _platform}
        method ptr {} {set _ptr}
        method id {} {set _ptr}
        lazy device string name
        lazy device string vendor
        lazy device string profile
        lazy device string version
        lazy device string extensions
        lazy device bool available
        lazy device uLong global_mem_size
    }

    oo::class create Platform {
        namespace path ::TclOpenCL
        variable _ptr

        constructor {id} {set _ptr $id}

        method ptr {} {set _ptr}
        method id {} {set _ptr}
        lazy platform string name
        lazy platform string vendor
        lazy platform string profile
        lazy platform string version
        lazy platform string extensions

        method devices {{type all} {idx ""}} {
            set clType [set ::CL_DEVICE_TYPE_[string toupper $type]]
            set deviceQuery [clGetDeviceIDs $_ptr $clType 0 NULL]
            if {[lindex $deviceQuery 0] == $::CL_DEVICE_NOT_FOUND} {
                return [list]
            }
            if {[lindex $deviceQuery 0] != $::CL_SUCCESS} {
                return -code error "Could not list OpenCL devices"
            }
            set count [lindex $deviceQuery 1]
            if {$count == 0} {
                return [list]
            }
            set deviceIds [new_cl_device_id_array $count]
            set ok [clGetDeviceIDs $_ptr $clType $count $deviceIds]
            if {[lindex $ok 0] != $::CL_SUCCESS} {
                return -code error "Could not list OpenCL devices"
            }
            for {set i 0} {$i < $count} {incr i} {
                set dev_id [cl_device_id_array_getitem $deviceIds $i]
                lappend devices [::TclOpenCL::Device new [self] $dev_id]
            }
            delete_cl_device_id_array $deviceIds
            if {$idx ne ""} {
                lindex $devices $idx
            } else {
                set devices
            }
        }
    }

    proc platforms {{idx ""}} {
        set platformQuery [clGetPlatformIDs 0 NULL]
        if {[lindex $platformQuery 0] != $::CL_SUCCESS} {
            return -code error "Could not list OpenCL platforms"
        }
        set count [lindex $platformQuery 1]
        if {$count == 0} {
            return [list]
        }
        set platformIds [new_cl_platform_id_array $count]
        set ok [clGetPlatformIDs $count $platformIds]
        if {[lindex $ok 0] != $::CL_SUCCESS} {
            return -code error "Could not list OpenCL platforms"
        }
        for {set i 0} {$i < $count} {incr i} {
            set id [cl_platform_id_array_getitem $platformIds $i]
            lappend platforms [Platform new $id]
        }
        delete_cl_platform_id_array $platformIds
        if {$idx ne ""} {
            lindex $platforms $idx
        } else {
            set platforms
        }
    }

    oo::class create Context {
        variable _ptr _platform _devices

        constructor {platform devices} {
            set _platform $platform
            set _devices $devices
            set platformId [$platform id]
            set count [llength $devices]
            set deviceIds [new_cl_device_id_array $count]
            for {set i 0} {$i < $count} {incr i} {
                cl_device_id_array_setitem $deviceIds $i [[lindex $devices $i] id]
            }
            set res [clCreateContextSafe $platformId $count $deviceIds]
            delete_cl_device_id_array $deviceIds
            if {[lindex $res 1] != $::CL_SUCCESS} {
                return -code error "Could not create OpenCL context"
            }
            set _ptr [lindex $res 0]
        }
        refcounted context

        method ptr {} {set _ptr}
        method platform {} {set _platform}
        method devices {} {set _devices}
    }

    oo::class create CommandQueue {
        variable _ptr _ctx _device

        constructor {ctx device args} {
            set _ctx $ctx
            set _device $device

            set opts [dict create {*}$args]

            if {[info exists ::CL_VERSION_2_0]} {
                set props [new_cl_command_queue_properties_array [expr [llength $args] + 1]]
                set qProps 0
                set i 0
                if {[dict exists $opts -outOfOrder]} {
                    set qProps [expr $qProps | $::CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE]
                }
                if {[dict exists $opts -onDevice]} {
                    set qProps [expr $qProps | $::CL_QUEUE_ON_DEVICE | $::CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE]
                    if {[dict exists $opts -default]} {
                        set qProps [expr $qProps | $::CL_QUEUE_ON_DEVICE_DEFAULT]
                    }
                }
                if {$qProps != 0} {
                    cl_command_queue_properties_array_setitem $props [incr i] $::CL_QUEUE_PROPERTIES
                    cl_command_queue_properties_array_setitem $props [incr i] $qProps
                }
                if {[dict exists $opts -size]} {
                    cl_command_queue_properties_array_setitem $props [incr i] $::CL_QUEUE_SIZE
                    cl_command_queue_properties_array_setitem $props [incr i] [dict get $opts -size]
                }
                cl_command_queue_properties_array_setitem $props [incr i] 0

                set res [clCreateCommandQueueWithProperties $ctx::_ptr [$device id] $props]
                delete_cl_command_queue_properties_array $props
            } else {
                set props 0
                if {[dict exists $opts -outOfOrder]} {
                    set props [expr $props | $::CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE]
                }
                set res [clCreateCommandQueue [$ctx ptr] [$device id] $props]
            }

            if {[lindex $res 1] != $::CL_SUCCESS} {
                return -code error "Could not create OpenCL command queue"
            }
            set _ptr [lindex $res 0]
        }
        refcounted commandQueue

        method ptr {} {set _ptr}
        method context {} {set _ctx}
        method device {} {set _device}
    }

    oo::class create Buffer {
        variable _ptr

        constructor {ctx arr args} {
            set opts [dict create {*}$args]
            set mode $::CL_MEM_READ_WRITE
            if {[dict exists $opts -mode]} {
                switch -glob [dict get $opts -mode] {
                    r* {set mode $::CL_MEM_READ_ONLY}
                    w* {set mode $::CL_MEM_WRITE_ONLY}
                    rw {set mode $::CL_MEM_READ_WRITE}
                }
            }
            set hostMode $::CL_MEM_USE_HOST_PTR
            if {[dict exists $opts -copy] && [dict get $opts -copy] eq yes} {
                set hostMode $::CL_MEM_COPY_HOST_PTR
            }
            set hostAccess 0
            if {[dict exists $opts -access]} {
                switch -glob [dict get $opts -access] {
                    r* {set hostAccess $::CL_MEM_HOST_READ_ONLY}
                    w* {set hostAccess $::CL_MEM_HOST_WRITE_ONLY}
                    no* {set hostAccess $::CL_MEM_HOST_NO_ACCESS}
                }
            }
            set flags [expr {$mode | $hostMode | $hostAccess}]
            # clCreateBufferFromNumArray always uses the numarray's size. Any
            # value will work for the size argument, so just use 0.
            set res [clCreateBufferFromNumArray [$ctx ptr] $flags $arr]
            if {[lindex $res 1] != $::CL_SUCCESS} {
                return -code error "Could not create OpenCL buffer"
            }
            set _ptr [lindex $res 0]
        }

        method ptr {} {set _ptr}
    }

    oo::class create Program {
        variable _ptr _src _kerns _hasArgInfo

        constructor {ctx code} {
            set res [clCreateProgramWithSource [$ctx ptr] 1 $code]
            if {[lindex $res 1] != $::CL_SUCCESS} {
                return -code error "Could not create OpenCL program"
            }
            set _src $code
            set _ptr [lindex $res 0]
        }
        refcounted program

        method ptr {} {set _ptr}
        method source {} {set _src}

        method buildForDevices {devices args} {
            set count [llength $devices]
            set dev_ids [new_cl_device_id_array $count]
            for {set i 0} {$i < $count} {incr i} {
                cl_device_id_array_setitem $dev_ids $i [[lindex $devices $i] id]
            }
            if {[lsearch -exact $args -cl-kernel-arg-info] > -1} {
                set _hasArgInfo 1
            } else {
                set _hasArgInfo 0
            }
            set ok [clBuildProgramSync $_ptr $count $dev_ids [concat {*}$args]]
            if {$ok != $::CL_SUCCESS} {
                return -code error "Could not build OpenCL program"
            }

            set me [self]
            foreach kname [$me kernelNames] {
                set kname [string trim $kname]
                oo::objdefine $me method $kname {args} "
                    my variable _kernels
                    if {\[array get _kernels $kname] != {}} {
                        if {\[llength \[set args]] == 0} {
                            return \[set _kernels($kname)]
                        }
                        return \[\[set _kernels($kname)] {*}\[set args]]
                    }
                    set kern \[clCreateKernel $_ptr $kname]
                    if {\[lindex \[set kern] 1] != $::CL_SUCCESS} {
                        return -code error {Could not retrieve OpenCL kernel '$kname'}
                    }
                    set kptr \[lindex \[set kern] 0]
                    set _kernels($kname) \[::TclOpenCL::Kernel new \[set kptr] $kname $_hasArgInfo]
                    if {\[llength \[set args]] == 0} {
                        return \[set _kernels($kname)]
                    }
                    return \[\[set _kernels($kname)] {*}\[set args]]
                "
            }

            self
        }

        method kernelNames {} {
            my variable _kernelNames
            if {[info exists _kernelNames]} {
                return $_kernelNames
            }

            set res [clGetProgramInfoString $_ptr $::CL_PROGRAM_KERNEL_NAMES]
            if {[lindex $res 0] != $::CL_SUCCESS} {
                return -code error "Could not query OpenCL kernel names"
            }
            set _kernelNames [split [lindex $res 1] ";"]
        }
    }

    oo::class create Kernel {
        variable _ptr _name _hasArgInfo

        constructor {ptr name hasArgInfo} {
            set _ptr $ptr
            set _name $name
            set _hasArgInfo $hasArgInfo
        }
        refcounted kernel

        method ptr {} {set _ptr}
        method name {} {set _name}
        lazy kernel uInt num_args
        lazy kernel string attributes

        method argType {idx} {
            my variable _argTypes
            if {[array get _argTypes $idx] != ""} {
                return _argTypes($idx)
            }

            if {$_hasArgInfo == 0} {
                return -code error "OpenCL kernel '$_name' not compiled with -cl-kernel-arg-info"
            }

            set res [clGetKernelArgInfoString $_ptr $idx $::CL_KERNEL_ARG_TYPE_NAME]
            if {[lindex $res 0] != $::CL_SUCCESS} {
                return -code error "Could not get type of OpenCL kernel '$_name' argument $idx"
            }
            set _argTypes($idx) [lindex $res 1]
        }

        method setArgs {arglist} {
            if {[llength $arglist] != [[self] numArgs]} {
                return -code error "OpenCL kernel '$_name' expects [[self] numArgs] arguments but got [llength $arglist]"
            }

            set i 0
            foreach arg $arglist {
                if {[string match -nocase null $arg]} {
                    if {[clSetKernelArgNull $_ptr $i] != $::CL_SUCCESS} {
                        return -code error "Failed to set argument $i of OpenCL kernel '$_name'"
                    }
                } elseif {[string match -nocase int(*) $arg] || [string is integer $arg]} {
                    if {[clSetKernelArgInt $_ptr $i [regsub -nocase {^int\((.*)?\)$} $arg {\1}]] != $::CL_SUCCESS} {
                        return -code error "Failed to set argument $i of OpenCL kernel '$_name'"
                    }
                } elseif {[string match -nocase uint(*) $arg] || [string match -nocase unsigned(*) $arg]} {
                    if {[clSetKernelArgUInt $_ptr $i [regsub -nocase {^(?:uint|unsigned)\((.*)?\)$} $arg {\1}]] != $::CL_SUCCESS} {
                        return -code error "Failed to set argument $i of OpenCL kernel '$_name'"
                    }
                } elseif {[string match -nocase long(*) $arg]} {
                    if {[clSetKernelArgLong $_ptr $i [regsub -nocase {^long\((.*)?\)$} $arg {\1}]] != $::CL_SUCCESS} {
                        return -code error "Failed to set argument $i of OpenCL kernel '$_name'"
                    }
                } elseif {[string match -nocase ulong(*) $arg]} {
                    if {[clSetKernelArgULong $_ptr $i [regsub -nocase {^ulong\((.*)?\)$} $arg {\1}]] != $::CL_SUCCESS} {
                        return -code error "Failed to set argument $i of OpenCL kernel '$_name'"
                    }
                } elseif {[string match -nocase float(*) $arg] || [string match -nocase single(*) $arg] || [string is double $arg]} {
                    if {[clSetKernelArgFloat $_ptr $i [regsub -nocase {^(?:float|single)\((.*)?\)$} $arg {\1}]] != $::CL_SUCCESS} {
                        return -code error "Failed to set argument $i of OpenCL kernel '$_name'"
                    }
                } elseif {[string match -nocase double(*) $arg]} {
                    if {[clSetKernelArgDouble $_ptr $i [regsub -nocase {^double\((.*)?\)$} $arg {\1}]] != $::CL_SUCCESS} {
                        return -code error "Failed to set argument $i of OpenCL kernel '$_name'"
                    }
                }

                incr i
            }

            self
        }

        method runBlocking {queue work_dims global_work_off global_work_sz local_work_sz args} {
            [self] setArgs $args
            set gwkoff [new_size_t_array $work_dims]
            set gwksz [new_size_t_array $work_dims]
            set lwksz [new_size_t_array $work_dims]
            for {set i 0} {$i < $work_dims} {incr i} {
                size_t_array_setitem $gwkoff $i [lindex $global_work_off $i]
                size_t_array_setitem $gwksz $i [lindex $global_work_sz $i]
                size_t_array_setitem $lwksz $i [lindex $local_work_sz $i]
            }
            set evts [new_cl_event_array 0]
            set evt_out [new_cl_event_array 1]
            set res [clEnqueueNDRangeKernel [$queue ptr] $_ptr $work_dims $gwkoff $gwksz $lwksz 0 $evts $evt_out]
            if {[lindex $res 0] != $::CL_SUCCESS} {
                return -code error "Failed to run OpenCL kernel '$_name'"
            }
        }
    }

    proc program {name body} {
        # TODO define an OpenCL program and kernels with a very thin DSL:
        # cl::program Foo {
        #   cl::kernel compute_stuff -ret void {__global float *a, __global float *b} {
        #     ...
        #   }
        # }
        # set f [[Foo new $ctx] buildForDevices $deviceList]
        # $f compute_stuff $a_vec $b_vec
    }
}
