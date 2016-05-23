# A VecTcl Extension For Parallel Numeric Computation on Heterogeneous Platforms

TclOpenCL provides both low-level and higher-level access to OpenCL 1.2+ APIs
via SWIG and a TclOO wrapper.

**THIS IS PROBABLY NOT USEFUL TO YOU YET**

## Installation

### Binaries

Building TclOpenCL on Windows is a bit of a pain. You can download binary releases [on GitHub](https://github.com/alpha123/TclOpenCL/releases). These have been verified to work with ActiveTcl 8.6 on 64-bit Windows 10 and the NVIDIA platform.

TclOpenCL requires [VecTcl](https://github.com/auriocus/VecTcl) and an OpenCL
implementation for your platform. Hacking on TclOpenCL requires
[SWIG](http://swig.org/).

- NVIDIA: Install the
  [NVIDIA CUDA SDK](https://developer.nvidia.com/cuda-downloads)
- AMD: Install the
  [AMD Accelerated Parallel Processing SDK](http://developer.amd.com/tools-and-sdks/opencl-zone/amd-accelerated-parallel-processing-app-sdk/)
- Intel CPU, HD Graphics, and Iris Graphics: Find the
  [Intel OpenCL Drivers](https://software.intel.com/en-us/articles/opencl-drivers)
  for your CPU and iGPU

Once that's installed, `git clone https://github.com/alpha123/TclOpenCL` and do
the standard `./configure; make install`. You may need to play with the
--with-opencl=path/to/opencl/lib/dir configure flag on Windows. Type
`./configure --help` to see other flags.

## Progress

What works:

- Create and query OpenCL devices and platforms
- Create command queues, contexts, and memory buffers
- Build OpenCL programs and query kernels
- Pass arguments to kernels and run them
- Do all of the above from a TclOO interface

What kind of works:

- Create memory buffers from VecTcl arrays
- Call kernels with VecTcl arrays as arguments

What doesn't work:

- Copy buffers back to VecTcl arrays....
- Fully asynchronous APIs based on OpenCL events
- A more pleasant way of managing workgroups
- A higher-level DSL for defining and running kernels
