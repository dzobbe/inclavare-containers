# Project name
if(SGX)
    project(intel-sgx-ssl)
endif()

include(ExternalProject)
include(FindSGXSSL)

# Patch
set(_patch_script "${CMAKE_CURRENT_SOURCE_DIR}/patch_script.sh")
file(WRITE "${_patch_script}"
"#!/bin/sh
cd ${INTEL_SGXSSL_SRC}/
if [ ! -e  Linux/sgx/libsgx_usgxssl/uunistd.cpp ]; then
        patch -p1 < ${CMAKE_CURRENT_SOURCE_DIR}/patch/0001-add-ssl-library-enclave-support.patch;
        #FixME: there are some format issues in project intel-sgx-ssl which fails to apply patch. So
        #use this workaround solution. Once the format issue is solved, copying source code will be
        #replaced.
        cp ${CMAKE_CURRENT_SOURCE_DIR}/patch/t*  Linux/sgx/libsgx_tsgxssl/
fi;
")

set(_patch_cmake "${CMAKE_CURRENT_SOURCE_DIR}/patch.cmake")
file(WRITE "${_patch_cmake}"
        "execute_process(COMMAND sh ${_patch_script} WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})"
)

# Configure
set(_configure_script "${CMAKE_CURRENT_SOURCE_DIR}/download_script.sh")
file(WRITE "${_configure_script}"
"#!/bin/sh
if [ ! -e ${OPENSSL_DIR}/openssl-1.1.1*.tar.gz ]; then
       wget --no-check-certificate https://www.openssl.org/source/openssl-1.1.1k.tar.gz -P ${OPENSSL_DIR};
fi;
")

set(_configure_cmake "${CMAKE_CURRENT_SOURCE_DIR}/configure.cmake")
file(WRITE "${_configure_cmake}"
        "execute_process(COMMAND sh ${_configure_script} WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})"
)

# Make
set(_make_script "${CMAKE_CURRENT_SOURCE_DIR}/intel_sgxssl_make.sh")
if(SGX)
    file(WRITE "${_make_script}"
"#!/bin/sh
cd ${INTEL_SGXSSL_SRC}/Linux
make
")
endif()

set(_make_cmake "${CMAKE_CURRENT_SOURCE_DIR}/make.cmake")
file(WRITE "${_make_cmake}"
"execute_process(COMMAND sh ${_make_script} WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})"
)

# Install
set(_install_script "${CMAKE_CURRENT_SOURCE_DIR}/sgxssl_install.sh")
if(SGX)
    file(WRITE "${_install_script}"
"#!/bin/sh
cd ${INTEL_SGXSSL_SRC}/Linux
install -d -m 0755 ${INTEL_SGXSSL_LIB_PATH}
install -m 0755 ${INTEL_SGXSSL_LIB}/libsgx_usgxssl.a ${INTEL_SGXSSL_LIB_PATH}/libsgx_usgxssl.a
install -m 0755 ${INTEL_SGXSSL_LIB}/libsgx_tsgxssl.a ${INTEL_SGXSSL_LIB_PATH}/libsgx_tsgxssl.a
install -m 0755 ${INTEL_SGXSSL_LIB}/libsgx_tsgxssl_crypto.a ${INTEL_SGXSSL_LIB_PATH}/libsgx_tsgxssl_crypto.a
install -m 0755 ${INTEL_SGXSSL_LIB}/libsgx_tsgxssl_ssl.a ${INTEL_SGXSSL_LIB_PATH}/libsgx_tsgxssl_ssl.a
#sudo make install DESTDIR=/opt/enclave-tls/sgxssl/
cd -
")
endif()

set(_install_cmake "${CMAKE_CURRENT_SOURCE_DIR}/install.cmake")
file(WRITE "${_install_cmake}"
        "execute_process(COMMAND sh ${_install_script} WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})"
)

# Set intel-sgx-ssl git and compile parameters
set(SGXSSL_URL           https://github.com/intel/intel-sgx-ssl/archive/refs/tags/lin_2.14_1.1.1k.tar.gz)
set(SGXSSL_DOWNLOAD_NAME lin_2.14_1.1.1k.tar.gz)
set(SGXSSL_MAKE          cd ${INTEL_SGXSSL_SRC}/Linux/ && make)

ExternalProject_Add(${PROJECT_NAME}
        PREFIX                  ${INTEL_SGXSSL_ROOT}
        URL                     ${SGXSSL_URL}
        URL_HASH                SHA256=aa6878fd2e541c500984c991032959bd991e80488db2f72ff908445d3fea13c7
        DOWNLOAD_NAME           ${SGXSSL_DOWNLOAD_NAME}
        PATCH_COMMAND           ${CMAKE_COMMAND} -P ${_patch_cmake}
        CONFIGURE_COMMAND       ${CMAKE_COMMAND} -P ${_configure_cmake}
        BUILD_COMMAND           ${CMAKE_COMMAND} -P ${_make_cmake}
        INSTALL_COMMAND         ${CMAKE_COMMAND} -P ${_install_cmake}
)