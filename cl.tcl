package provide TclOpenCL 0.1
package require TclOO

namespace eval ::TclOpenCL {
    namespace export Context platforms

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

    oo::class create Device {
        variable _platform _id

        constructor {platform id} {
            set _platform $platform
            set _id $id
        }
        # Following two functions are just for subdevices and have no affect if
        # this is a root-level device.
        destructor {
            if {[clReleaseDevice $_id] != $::CL_SUCCESS} {
                return -code error "Could not release OpenCL device"
            }
        }
        method <cloned> {_} {
            if {[clRetainDevice $_id] != $::CL_SUCCESS} {
                return -code error "Could not retain OpenCL device"
            }
        }

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
            if {[lindex $res 1] != $::CL_SUCCESS} {
                return -code error "Could not create OpenCL context"
            }
            set _ptr [lindex $res 0]
            delete_cl_device_id_array $deviceIds
        }
        destructor {
            if {[clReleaseContext $_ptr] != $::CL_SUCCESS} {
                return -code error "Could not release OpenCL context"
            }
        }
        method <cloned> {_} {
            if {[clRetainContext $_ptr] != $::CL_SUCCESS} {
                return -code error "Could not retain OpenCL context"
            }
        }

        method platform {} {set _platform}
        method devices {} {set _devices}
    }
}
