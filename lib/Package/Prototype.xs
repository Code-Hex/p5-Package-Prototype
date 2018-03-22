#ifdef __cplusplus
extern "C" {
#endif

#define PERL_NO_GET_CONTEXT /* we want efficiency */
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#ifdef __cplusplus
} /* extern "C" */
#endif

#define NEED_newSVpvn_flags
#include "ppport.h"

#define IsArrayRef(sv) (SvROK(sv) && !SvOBJECT(SvRV(sv)) && SvTYPE(SvRV(sv)) == SVt_PVAV)
#define IsHashRef(sv) (SvROK(sv) && !SvOBJECT(SvRV(sv)) && SvTYPE(SvRV(sv)) == SVt_PVHV)
#define IsCodeRef(sv) (SvROK(sv) && !SvOBJECT(SvRV(sv)) && SvTYPE(SvRV(sv)) == SVt_PVCV)
#define WANT_ARRAY GIMME_V == G_ARRAY

static void
push_values(pTHX_ SV *retval)
{
    dSP;
    if (WANT_ARRAY && IsArrayRef(retval)) {
        AV *av  = (AV *)SvRV(retval);
        I32 len = av_len(av) + 1;
        EXTEND(SP, len);
        for (I32 i = 0; i < len; i++){
            SV **const svp = av_fetch(av, i, FALSE);
            PUSHs(svp ? *svp : &PL_sv_undef);
        }
    } else if (WANT_ARRAY && IsHashRef(retval)) {
        HV *hv = (HV *)SvRV(retval);
        HE *he;
        hv_iterinit(hv);
        while ((he = hv_iternext(hv)) != NULL){
            EXTEND(SP, 2);
            PUSHs(hv_iterkeysv(he));
            PUSHs(hv_iterval(hv, he));
        }
    } else {
        XPUSHs(retval ? retval : &PL_sv_undef);
    }
    PUTBACK;
}

XS(XS_prototype_getter)
{
    dVAR; dXSARGS;
    SV *retval = (SV *)CvXSUBANY(cv).any_ptr;
    SP -= items; /* PPCODE */
    PUTBACK;
    push_values(aTHX_ retval);
}

static GV *
prototype_gv_pvn(pTHX_ HV *stash, const char *name, STRLEN len, U32 flags)
{
    GV *gv = (GV *)newSV(0);
    gv_init_pvn(gv, stash, name, len, flags);
    return gv;
}

static GV *
prototype_gv_sv(pTHX_ HV *stash, SV *namesv)
{
    U32 flag;
    char *namepv;
    STRLEN namelen;
    namepv = SvPV(namesv, namelen);
    if (SvUTF8(namesv)) flag = SVf_UTF8;
    return prototype_gv_pvn(aTHX_ stash, namepv, namelen, flag);
}

static void
add_method(pTHX_ HV *stash, SV *method, CV *code, char *key, I32 keylen)
{
    GV *gv;
    gv = prototype_gv_sv(aTHX_ stash, method);
    GvCV_set(gv, code);
    hv_store(stash, key, keylen, (SV *)gv, 0);
}

static CV *
make_closure(pTHX_ SV *retval)
{
    CV *xsub;
    xsub = newXS(NULL /* anonymous */, XS_prototype_getter, __FILE__);
    CvXSUBANY(xsub).any_ptr = (void *)retval;
    return xsub;
}

MODULE = Package::Prototype    PACKAGE = Package::Prototype
PROTOTYPES: DISABLE

void *
bless(klass, ref, pkgsv=NULL)
    SV *klass;
    SV *ref;
    SV *pkgsv;
PREINIT:
    char *pkg;
    STRLEN pkglen;
    HE* entry;
    HV *stash;
PPCODE:
{
    if (!IsHashRef(ref))
         Perl_croak(aTHX_ "Please pass an hash reference to the first argument");

    if (pkgsv) {
        pkg = SvPV(pkgsv, pkglen);
    } else {
        pkg = "__ANON__";
        pkglen = 8;
    }

    stash = (HV *)sv_2mortal((SV *)newHV());
    hv_name_set(stash, pkg, pkglen, 0);

    HV *hv = (HV *)SvRV(ref);
    hv_iterinit(hv);
    while ((entry = hv_iternext(hv)) != NULL){
        I32 keylen;
        char* key = hv_iterkey(entry, &keylen);
        if (0 < keylen && key[0] != '_') {
            SV *method = hv_iterkeysv(entry);
            SV *val = hv_delete(hv, key, keylen, 1);
            SvREFCNT_inc(val); /* was made mortal by hv_delete */
            CV *cv = IsCodeRef(val) ? (CV *)SvRV(val) : make_closure(aTHX_ val);
            add_method(aTHX_ stash, method, cv, key, keylen);
        }
    }

    ST(0) = sv_bless(ref, stash);
    XSRETURN(1);
}