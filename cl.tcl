package provide TclOpenCL 0.1
package require TclOO
package require vectcl

tclOpenCLInit 0

namespace eval ::TclOpenCL {
    namespace export Buffer Context CommandQueue platforms

    proc capitalize {s} {
        string replace $s 0 0 [string toupper [string index $s 0]]
    }

    proc ::oo::define::lazy {type name {family "device"}} {
        set clInfoType [set ::CL_[string toupper $family]_[string toupper $name]]
        set clInfoProc clGet[::TclOpenCL::capitalize $family]Info[::TclOpenCL::capitalize $type]
        set body [concat "{ my variable _$name; " if "{\[info exists _$name]} {
            set _$name
        }" else "{
            set query \[$clInfoProc \[set _id] $clInfoType]
            if {\[lindex \[set query] 0] != $::CL_SUCCESS} {
                return -code error {Could not query OpenCL device $name}
            }
            set _$name \[lindex \[set query] 1]
        } }"]
        uplevel 1 method $name "{}" $body
    }

    proc ::oo::define::refcounted {family {cHandle "_ptr"}} {
        set retain clRetain[::TclOpenCL::capitalize $family]
        set release clRelease[::TclOpenCL::capitalize $family]
        set destructor [concat "{ if {\[$release \[set $cHandle]] != $::CL_SUCCESS} {
            return -code error {Could not release OpenCL $family}
        } }"]
        set cloned [concat "{ if {\[$retain \[set $cHandle]] != $::CL_SUCCESS} {
            return -code error {Could not retain OpenCL $family}
        } }"]
        uplevel 1 destructor $destructor
        uplevel 1 method <cloned> "{_}" $cloned
    }

    oo::class create Device {
        variable _platform _id

        constructor {platform id} {
            set _platform $platform
            set _id $id
        }
        # Memory management is just for subdevices and has no affect if this is
        # a root-level device.
        refcounted device _id

        method platform {} {set _platform}
        method id {} {set _id}
        lazy string name
        lazy string vendor
        lazy string profile
        lazy string version
        lazy string extensions
        lazy bool available
        lazy uLong global_mem_size
    }

    oo::class create Platform {
        namespace path ::TclOpenCL
        variable _id

        constructor {id} {set _id $id}

        method id {} {set _id}
        lazy string name platform
        lazy string vendor platform
        lazy string profile platform
        lazy string version platform
        lazy string extensions platform

        method devices {{type all} {idx ""}} {
            set clType [set ::CL_DEVICE_TYPE_[string toupper $type]]
            set deviceQuery [clGetDeviceIDs $_id $clType 0 NULL]
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
            set ok [clGetDeviceIDs $_id $clType $count $deviceIds]
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
}
