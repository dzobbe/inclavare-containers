/* Copyright (c) 2020-2021 Alibaba Cloud and Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */
use crate::policyEngine::opa::opaEngine::*;
use base64;
use foreign_types::{ForeignType, ForeignTypeRef, Opaque};
use std::ops::{Deref, DerefMut};
use std::os::unix::io::RawFd;
use std::ptr::NonNull;

mod ffi;
use ffi::*;

pub struct EnclaveTlsRef(Opaque);

unsafe impl ForeignTypeRef for EnclaveTlsRef {
    type CType = enclave_tls_handle;
}

#[derive(Clone)]
pub struct EnclaveTls(NonNull<enclave_tls_handle>);

unsafe impl Send for EnclaveTlsRef {}
unsafe impl Sync for EnclaveTlsRef {}
unsafe impl Send for EnclaveTls {}
unsafe impl Sync for EnclaveTls {}

unsafe impl ForeignType for EnclaveTls {
    type CType = enclave_tls_handle;
    type Ref = EnclaveTlsRef;

    unsafe fn from_ptr(ptr: *mut enclave_tls_handle) -> EnclaveTls {
        EnclaveTls(NonNull::new_unchecked(ptr))
    }

    fn as_ptr(&self) -> *mut enclave_tls_handle {
        self.0.as_ptr()
    }

    fn into_ptr(self) -> *mut enclave_tls_handle {
        let inner = self.as_ptr();
        ::core::mem::forget(self);
        inner
    }
}

impl Drop for EnclaveTls {
    fn drop(&mut self) {
        unsafe {
            enclave_tls_cleanup(self.as_ptr());
        }
    }
}

impl Deref for EnclaveTls {
    type Target = EnclaveTlsRef;

    fn deref(&self) -> &EnclaveTlsRef {
        unsafe { EnclaveTlsRef::from_ptr(self.as_ptr()) }
    }
}

impl DerefMut for EnclaveTls {
    fn deref_mut(&mut self) -> &mut EnclaveTlsRef {
        unsafe { EnclaveTlsRef::from_ptr_mut(self.as_ptr()) }
    }
}

impl EnclaveTls {
    pub fn new(
        server: bool,
        enclave_id: u64,
        tls_type: &Option<String>,
        crypto: &Option<String>,
        attester: &Option<String>,
        verifier: &Option<String>,
        mutual: bool,
    ) -> Result<EnclaveTls, enclave_tls_err_t> {
        let mut conf: enclave_tls_conf_t = Default::default();
        conf.api_version = ENCLAVE_TLS_API_VERSION_DEFAULT;
        conf.log_level = ENCLAVE_TLS_LOG_LEVEL_DEBUG;
        if let Some(tls_type) = tls_type {
            conf.tls_type[..tls_type.len()].copy_from_slice(tls_type.as_bytes());
        }
        if let Some(crypto) = crypto {
            conf.crypto_type[..crypto.len()].copy_from_slice(crypto.as_bytes());
        }
        if let Some(attester) = attester {
            conf.attester_type[..attester.len()].copy_from_slice(attester.as_bytes());
        }
        if let Some(verifier) = verifier {
            conf.verifier_type[..verifier.len()].copy_from_slice(verifier.as_bytes());
        }
        conf.cert_algo = ENCLAVE_TLS_CERT_ALGO_DEFAULT;
        conf.enclave_id = enclave_id;
        if mutual {
            conf.flags |= ENCLAVE_TLS_CONF_FLAGS_MUTUAL;
        }
        if server {
            conf.flags |= ENCLAVE_TLS_CONF_FLAGS_SERVER;
        }

        let mut handle: enclave_tls_handle = unsafe { std::mem::zeroed() };
        let mut tls: *mut enclave_tls_handle = &mut handle;
        let err = unsafe { enclave_tls_init(&conf, &mut tls) };
        if err != ENCLAVE_TLS_ERR_NONE {
            println!("enclave_tls_init() failed");
            return Err(err);
        }

        let err = unsafe { enclave_tls_set_verification_callback(&mut tls, Some(Self::callback)) };
        if err == ENCLAVE_TLS_ERR_NONE {
            Ok(unsafe { EnclaveTls::from_ptr(tls) })
        } else {
            Err(err)
        }
    }

    pub fn negotiate(&self, fd: RawFd) -> Result<(), enclave_tls_err_t> {
        let err = unsafe { enclave_tls_negotiate(self.as_ptr(), fd) };
        if err == ENCLAVE_TLS_ERR_NONE {
            Ok(())
        } else {
            Err(err)
        }
    }

    pub fn receive(&self, buf: &mut [u8]) -> Result<usize, enclave_tls_err_t> {
        let mut len: size_t = buf.len() as size_t;
        let err = unsafe {
            enclave_tls_receive(
                self.as_ptr(),
                buf.as_mut_ptr() as *mut ::std::os::raw::c_void,
                &mut len,
            )
        };
        if err == ENCLAVE_TLS_ERR_NONE {
            Ok(len as usize)
        } else {
            Err(err)
        }
    }

    pub fn transmit(&self, buf: &[u8]) -> Result<usize, enclave_tls_err_t> {
        let mut len: size_t = buf.len() as size_t;
        let err = unsafe {
            enclave_tls_transmit(
                self.as_ptr(),
                buf.as_ptr() as *const ::std::os::raw::c_void,
                &mut len,
            )
        };
        if err == ENCLAVE_TLS_ERR_NONE {
            Ok(len as usize)
        } else {
            Err(err)
        }
    }

    fn sgx_callback(ev: etls_sgx_evidence_t) -> Result<(), String> {
        let mr_enclave =
            base64::encode(unsafe { std::slice::from_raw_parts(ev.mr_enclave, 32).to_vec() });
        let mr_signer =
            base64::encode(unsafe { std::slice::from_raw_parts(ev.mr_signer, 32).to_vec() });

        let message = serde_json::json!({
            "mrEnclave": mr_enclave,
            "mrSigner": mr_signer,
            "productId": ev.product_id,
            "svn": ev.security_version
        });

        make_decision("attestation.rego", &message.to_string())
            .map_err(|e| format!("make_decision error: {}", e))
            .and_then(|res| {
                serde_json::from_str(&res).map_err(|_| "Json unmashall failed".to_string())
            })
            .and_then(|res: serde_json::Value| {
                if res["allow"] == true {
                    Ok(())
                } else {
                    println!("parseInfo: {}", res["parseInfo"].to_string());
                    Err("decision is false".to_string())
                }
            })
    }

    #[no_mangle]
    extern "C" fn callback(evidence: *mut ::std::os::raw::c_void) -> ::std::os::raw::c_int {
        println!("Verdictd Enclave-TLS callback function is called.");
        let evidence = evidence as *mut etls_evidence;
        let res = if unsafe { (*evidence).type_ } == enclave_evidence_type_t_SGX_ECDSA {
            Self::sgx_callback(unsafe { (*evidence).__bindgen_anon_1.sgx })
        } else {
            Err("Not implemented".to_string())
        };

        let allow = match res {
            Ok(_) => 1,
            Err(e) => {
                println!("error: {}", e);
                0
            }
        };

        allow
    }
}
