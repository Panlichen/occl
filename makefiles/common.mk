#
# Copyright (c) 2015-2022, NVIDIA CORPORATION. All rights reserved.
#
# See LICENSE.txt for license information
#

CUDA_HOME ?= /usr/local/cuda
PREFIX ?= /usr/local
VERBOSE ?= 0
KEEP ?= 0
DEBUG ?= 0
TRACE ?= 0
PROFAPI ?= 0
NVTX ?= 1

NVCC = $(CUDA_HOME)/bin/nvcc

CUDA_LIB ?= $(CUDA_HOME)/lib64
CUDA_INC ?= $(CUDA_HOME)/include
CUDA_VERSION = $(strip $(shell which $(NVCC) >/dev/null && $(NVCC) --version | grep release | sed 's/.*release //' | sed 's/\,.*//'))
#CUDA_VERSION ?= $(shell ls $(CUDA_LIB)/libcudart.so.* | head -1 | rev | cut -d "." -f -2 | rev)
CUDA_MAJOR = $(shell echo $(CUDA_VERSION) | cut -d "." -f 1)
CUDA_MINOR = $(shell echo $(CUDA_VERSION) | cut -d "." -f 2)
#$(info CUDA_VERSION ${CUDA_MAJOR}.${CUDA_MINOR})

# # You should define NVCC_GENCODE in your environment to the minimal set
# # of archs to reduce compile time.
# CUDA8_GENCODE = -gencode=arch=compute_35,code=sm_35 \
#                 -gencode=arch=compute_50,code=sm_50 \
#                 -gencode=arch=compute_60,code=sm_60 \
#                 -gencode=arch=compute_61,code=sm_61
# CUDA9_GENCODE = -gencode=arch=compute_70,code=sm_70
# CUDA11_GENCODE = -gencode=arch=compute_80,code=sm_80

# CUDA8_PTX     = -gencode=arch=compute_61,code=compute_61
# CUDA9_PTX     = -gencode=arch=compute_70,code=compute_70
# CUDA11_PTX    = -gencode=arch=compute_80,code=compute_80

# # Include Ampere support if we're using CUDA11 or above
# ifeq ($(shell test "0$(CUDA_MAJOR)" -ge 11; echo $$?),0)
#   NVCC_GENCODE ?= $(CUDA8_GENCODE) $(CUDA9_GENCODE) $(CUDA11_GENCODE) $(CUDA11_PTX)
# # Include Volta support if we're using CUDA9 or above
# else ifeq ($(shell test "0$(CUDA_MAJOR)" -ge 9; echo $$?),0)
#   NVCC_GENCODE ?= $(CUDA8_GENCODE) $(CUDA9_GENCODE) $(CUDA9_PTX)
# else
#   NVCC_GENCODE ?= $(CUDA8_GENCODE) $(CUDA8_PTX)
# endif
# #$(info NVCC_GENCODE is ${NVCC_GENCODE})

# ref https://en.wikipedia.org/wiki/CUDA#Version_features_and_specifications
# we use GeForce 2080Ti(7.5) and 3080Ti(8.6, also for A40, A16, A10, A2), may use V100(7.0) and A100(8.0)
CUDA_GENCODE_3080   = -gencode=arch=compute_86,code=sm_86
CUDA_GENCODE_2080   = -gencode=arch=compute_75,code=sm_75
# CUDA_GENCODE_MAYUSE = -gencode=arch=compute_70,code=sm_70 \
#                       -gencode=arch=compute_80,code=sm_80                 

# 看上边的写法，PTX是只保留最大的那个。gencode "fatbin"，与硬件匹配。假如在不匹配的硬件上跑，那么会通过ptx的汇编代码转换过去。平时开发可以把ptx注释掉，加速编译。
# CUDA_PTX_INUSE      = -gencode=arch=compute_86,code=compute_86
# CUDA_PTX_INUSE      = -gencode=arch=compute_75,code=compute_75 \
#                       -gencode=arch=compute_86,code=compute_86
# CUDA_PTX_MAYUSE     = -gencode=arch=compute_70,code=compute_70 \
#                       -gencode=arch=compute_80,code=compute_80

CARDNAME ?= 3080
ifeq ($(CARDNAME), 3080)
NVCC_GENCODE ?= $(CUDA_GENCODE_3080) $(CUDA_PTX_INUSE)
else
NVCC_GENCODE ?= $(CUDA_GENCODE_2080) $(CUDA_PTX_INUSE)
endif
$(info CARDNAME $(CARDNAME))
$(info NVCC_GENCODE $(NVCC_GENCODE))

CXXFLAGS   := -DCUDA_MAJOR=$(CUDA_MAJOR) -DCUDA_MINOR=$(CUDA_MINOR) -fPIC -fvisibility=hidden \
              -Wall -Wno-unused-function -Wno-sign-compare -std=c++11 -Wvla \
              -I $(CUDA_INC) \
              $(CXXFLAGS)
# Maxrregcount needs to be set accordingly to NCCL_MAX_NTHREADS (otherwise it will cause kernel launch errors)
# 512 : 120, 640 : 96, 768 : 80, 1024 : 60
# We would not have to set this if we used __launch_bounds__, but this only works on kernels, not on functions.
NVCUFLAGS  := -ccbin $(CXX) $(NVCC_GENCODE) -std=c++11 --expt-extended-lambda -Xptxas -maxrregcount=96 -Xfatbin -compress-all
# Use addprefix so that we can specify more than one path
NVLDFLAGS  := -L${CUDA_LIB} -lcudart -lrt

########## GCOV ##########
GCOV ?= 0 # disable by default.
GCOV_FLAGS := $(if $(filter 0,${GCOV} ${DEBUG}),,--coverage) # only gcov=1 and debug =1
CXXFLAGS  += ${GCOV_FLAGS}
NVCUFLAGS += ${GCOV_FLAGS:%=-Xcompiler %}
LDFLAGS   += ${GCOV_FLAGS}
NVLDFLAGS   += ${GCOV_FLAGS:%=-Xcompiler %}
# $(warning GCOV_FLAGS=${GCOV_FLAGS})
########## GCOV ##########

ifeq ($(DEBUG), 0)
NVCUFLAGS += -O3
# TODO: CXXFLAGS  += -O3 -g
CXXFLAGS  += -O0 -g -ggdb3
else
NVCUFLAGS += -O0 -G -g
CXXFLAGS  += -O0 -g -ggdb3
endif

ifneq ($(VERBOSE), 0)
NVCUFLAGS += -Xptxas -v -Xcompiler -Wall,-Wextra,-Wno-unused-parameter
CXXFLAGS  += -Wall -Wextra
else
.SILENT:
endif

ifneq ($(TRACE), 0)
CXXFLAGS  += -DENABLE_TRACE
endif

ifeq ($(NVTX), 0)
CXXFLAGS  += -DNVTX_DISABLE
endif

ifneq ($(KEEP), 0)
NVCUFLAGS += -keep
endif

ifneq ($(PROFAPI), 0)
CXXFLAGS += -DPROFAPI
endif
