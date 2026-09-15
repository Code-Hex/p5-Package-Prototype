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

#define NEED_mg_findext
#define NEED_newSVpvn_flags
#include "ppport.h"

#ifndef GvCV_set
# define GvCV_set(gv,cv) (GvGP(gv)->gp_cv = (cv))
#endif

#ifndef gv_init_pvn
# define gv_init_pvn gv_init
#endif

#define IsArrayRef(sv) (SvROK(sv) && !SvOBJECT(SvRV(sv)) && SvTYPE(SvRV(sv)) == SVt_PVAV)
#define IsHashRef(sv) (SvROK(sv) && !SvOBJECT(SvRV(sv)) && SvTYPE(SvRV(sv)) == SVt_PVHV)
#define IsCodeRef(sv) (SvROK(sv) && !SvOBJECT(SvRV(sv)) && SvTYPE(SvRV(sv)) == SVt_PVCV)
#ifndef OpSIBLING
# define OpSIBLING(o) ((o)->op_sibling)
# define OpHAS_SIBLING(o) (OpSIBLING(o) != NULL)
#endif

#define WANT_ARRAY GIMME_V == G_ARRAY

XS(XS_prototype_method);
XS(XS_prototype_getter);

static MGVTBL getter_vtbl = { 0 };
static MGVTBL object_vtbl = { 0 };
static MGVTBL accessor_vtbl = { 0 };

static HV *
object_metadata(pTHX_ SV *object)
{
    MAGIC *magic;
    if (!SvROK(object) || !SvOBJECT(SvRV(object)))
        croak("Expected a Package::Prototype object");
    magic = mg_findext((SV *)SvSTASH(SvRV(object)), PERL_MAGIC_ext, &object_vtbl);
    if (!magic) croak("Expected a Package::Prototype object");
    return (HV *)magic->mg_obj;
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
    U32 flag = 0;
    char *namepv;
    STRLEN namelen;
    namepv = SvPV(namesv, namelen);
    if (SvUTF8(namesv)) flag = SVf_UTF8;
    return prototype_gv_pvn(aTHX_ stash, namepv, namelen, flag);
}

static HV *
stash_metadata(pTHX_ HV *stash)
{
    MAGIC *magic = mg_findext((SV *)stash, PERL_MAGIC_ext, &object_vtbl);
    return magic ? (HV *)magic->mg_obj : NULL;
}

static HV *
inherited_members(pTHX_ HV *metadata)
{
    SV **entry = hv_fetch(metadata, "inherited", 9, 0);
    if (!entry) {
        hv_store(metadata, "inherited", 9, newRV_noinc((SV *)newHV()), 0);
        entry = hv_fetch(metadata, "inherited", 9, 0);
    }
    return (HV *)SvRV(*entry);
}

static int
has_member(pTHX_ HV *stash, SV *name)
{
    HE *entry = hv_fetch_ent(stash, name, 0, 0);
    SV *value = entry ? HeVAL(entry) : NULL;
    return value && isGV(value) && !GvCVGEN((GV *)value) && GvCV((GV *)value);
}

static void
install_method(pTHX_ HV *stash, SV *method, CV *code, int own)
{
    HV *metadata = stash_metadata(aTHX_ stash);
    GV *gv;
    SV **children;
    /* A replaced closure can own other objects; pin the new CV during updates. */
    sv_2mortal(SvREFCNT_inc((SV *)code));
    if (metadata) {
        HV *inherited = inherited_members(aTHX_ metadata);
        if (own) hv_delete_ent(inherited, method, G_DISCARD, 0);
        else hv_store_ent(inherited, method, newSViv(1), 0);
    }
    gv = prototype_gv_sv(aTHX_ stash, method);
    GvCV_set(gv, code);
    hv_store_ent(stash, method, (SV *)gv, 0);
#if PERL_VERSION >= 10
    mro_method_changed_in(stash);
#else
    PL_sub_generation++;
#endif
    if (metadata && (children = hv_fetch(metadata, "children", 8, 0))) {
        AV *list = (AV *)SvRV(*children);
        I32 i;
        sv_2mortal(SvREFCNT_inc((SV *)list));
        for (i = 0; i <= av_len(list); i++) {
            SV **child = av_fetch(list, i, 0);
            HV *child_stash, *child_meta;
            SV **parent;
            if (!child || !SvROK(*child)) continue;
            sv_2mortal(newSVsv(*child));
            child_stash = SvSTASH(SvRV(*child));
            child_meta = stash_metadata(aTHX_ child_stash);
            if (!child_meta) continue; /* The object may have been reblessed. */
            parent = hv_fetch(child_meta, "parent", 6, 0);
            if (!parent || !SvROK(*parent) || SvSTASH(SvRV(*parent)) != stash) continue;
            if (!has_member(aTHX_ child_stash, method)
                || hv_exists_ent(inherited_members(aTHX_ child_meta), method, 0))
                install_method(aTHX_ child_stash, method, (CV *)SvREFCNT_inc((SV *)code), 0);
        }
    }
}

static void
add_method_sv(pTHX_ HV *stash, SV *method, CV *code)
{
    install_method(aTHX_ stash, method, code, 1);
}

static CV *
make_closure(pTHX_ SV *retval)
{
    /* Release the destination even when fetching magic throws on older Perls. */
    SV *value = sv_newmortal();
    sv_setsv(value, retval);
    CV *xsub = newXS(NULL /* anonymous */, XS_prototype_getter, __FILE__);
    /* Magic owns the scalar for exactly as long as the getter CV. */
    sv_magicext((SV *)xsub, value, PERL_MAGIC_ext, &getter_vtbl, NULL, 0);
    return xsub;
}

static void
push_values(pTHX_ SV *retval)
{
    dSP;
    /* A later argument can replace the getter and release its owned values. */
    if (WANT_ARRAY && IsArrayRef(retval)) {
        AV *av  = (AV *)SvRV(retval);
        I32 len = av_len(av) + 1;
        EXTEND(SP, len);
        for (I32 i = 0; i < len; i++){
            SV **const svp = av_fetch(av, i, FALSE);
            PUSHs(svp ? sv_2mortal(SvREFCNT_inc(*svp)) : &PL_sv_undef);
        }
    } else if (WANT_ARRAY && IsHashRef(retval)) {
        HV *hv = (HV *)SvRV(retval);
        HE *he;
        hv_iterinit(hv);
        while ((he = hv_iternext(hv)) != NULL){
            EXTEND(SP, 2);
            PUSHs(hv_iterkeysv(he));
            PUSHs(sv_2mortal(SvREFCNT_inc(hv_iterval(hv, he))));
        }
    } else {
        XPUSHs(retval ? sv_2mortal(SvREFCNT_inc(retval)) : &PL_sv_undef);
    }
    PUTBACK;
}

static CV *
make_prototype_method(pTHX)
{
    CV *xsub;
    xsub = newXS(NULL /* anonymous */, XS_prototype_method, __FILE__);
    return xsub;
}

static void
install_prototype_method(pTHX_ HV *stash)
{
    char *prototype = "prototype";
    CV *prototype_cv = make_prototype_method(aTHX);
    GV *prototype_glob = prototype_gv_pvn(aTHX_ stash, prototype, 9, 0);
    GvCV_set(prototype_glob, prototype_cv);
    hv_store(stash, prototype, 9, (SV *)prototype_glob, 0);
}

XS(XS_prototype_getter)
{
    dVAR; dXSARGS;
    SV *retval = mg_findext((SV *)cv, PERL_MAGIC_ext, &getter_vtbl)->mg_obj;
    SP -= items; /* PPCODE */
    PUTBACK;
    push_values(aTHX_ retval);
}

XS(XS_prototype_method)
{
    dVAR; dXSARGS;
    if ((items - 1) % 2 != 0)
        Perl_croak(aTHX_ "Argument isn't hash type");
    
    if (items < 1 || !SvROK(ST(0)) || !SvOBJECT(SvRV(ST(0))))
        Perl_croak(aTHX_ "prototype requires an object invocant");
    HV *stash = SvSTASH(SvRV(ST(0)));
    I32 i = 1; /* First argument is skip: `my $self = shift;` */
    while (i < items) {
        SV *method = ST(i++);
        STRLEN namelen;
        const char *name = SvPV(method, namelen);
        method = sv_2mortal(newSVpvn_flags(name, namelen, SvUTF8(method) ? SVf_UTF8 : 0));
        SV *val = ST(i++);
        CV *cv = IsCodeRef(val) ? (CV *)SvREFCNT_inc(SvRV(val)) : make_closure(aTHX_ val);
        add_method_sv(aTHX_ stash, method, cv);
    }
    XSRETURN(0);
}

/* A call checker only sees direct calls resolved during compilation. */
#if PERL_VERSION >= 16
/* Reconstruct literal values from safe syntax tree nodes (OP_CONST, OP_UNDEF,
 * OP_ANONLIST, OP_ANONHASH). Does not execute arbitrary opcodes. */
static SV *
literal_value(pTHX_ OP *op, unsigned depth)
{
    OP *child;
    SV *result;
    if (!op || depth > 64) return NULL;
    if (op->op_type == OP_CONST) {
        SV *value = cSVOPx_sv(op);
        if (SvROK(value) || SvMAGICAL(value)) return NULL;
        return sv_2mortal(newSVsv(value));
    }
    if (op->op_type == OP_UNDEF && !(op->op_flags & OPf_KIDS))
        return sv_2mortal(newSV(0));
    if (op->op_type != OP_ANONLIST && op->op_type != OP_ANONHASH)
        return NULL;
    if (!(op->op_flags & OPf_KIDS)) return NULL;
    child = cUNOPx(op)->op_first;
    if (child->op_type != OP_PUSHMARK) return NULL;
    child = OpSIBLING(child);
    result = sv_2mortal(newRV_noinc(op->op_type == OP_ANONLIST
        ? (SV *)newAV() : (SV *)newHV()));
    while (child) {
        SV *value = literal_value(aTHX_ child, depth + 1);
        if (!value) return NULL;
        if (op->op_type == OP_ANONLIST) {
            av_push((AV *)SvRV(result), SvREFCNT_inc(value));
        } else {
            SV *key = value;
            child = OpSIBLING(child);
            if (!child || !SvOK(key) || SvROK(key)) return NULL;
            value = literal_value(aTHX_ child, depth + 1);
            if (!value) return NULL;
            hv_store_ent((HV *)SvRV(result), key, SvREFCNT_inc(value), 0);
        }
        child = OpSIBLING(child);
    }
    return result;
}

/* Compile-time AST node representation:
 *   Kind 0: Literal constant (payload = scalar or reference)
 *   Kind 1: Unknown or deferred expression (payload = NULL)
 *   Kind 2: Array structure (payload = reference to an AV of child nodes)
 *   Kind 3: Hash structure (payload = reference to an HV of child nodes)
 */
static SV *
validation_node(pTHX_ int kind, SV *payload)
{
    AV *node = newAV();
    SV *result = sv_2mortal(newRV_noinc((SV *)node));
    av_push(node, newSViv(kind));
    if (payload) av_push(node, SvREFCNT_inc(payload));
    return result;
}

static SV *
structure_node(pTHX_ OP *op, unsigned depth)
{
    OP *child;
    SV *value, *payload;
    if (!op || depth > 64) return validation_node(aTHX_ 1, NULL);
    value = literal_value(aTHX_ op, depth);
    if (value) return validation_node(aTHX_ 0, value);
    if (op->op_type != OP_ANONLIST && op->op_type != OP_ANONHASH)
        return validation_node(aTHX_ 1, NULL);
    if (!(op->op_flags & OPf_KIDS)) return validation_node(aTHX_ 1, NULL);
    child = cUNOPx(op)->op_first;
    if (child->op_type != OP_PUSHMARK) return validation_node(aTHX_ 1, NULL);
    payload = sv_2mortal(newRV_noinc(op->op_type == OP_ANONLIST
        ? (SV *)newAV() : (SV *)newHV()));
    child = OpSIBLING(child);
    while (child) {
        SV *key = NULL;
        if (op->op_type == OP_ANONHASH) {
            key = literal_value(aTHX_ child, depth + 1);
            if (!key || !SvOK(key) || SvROK(key)) return validation_node(aTHX_ 1, NULL);
            child = OpSIBLING(child);
            if (!child) return validation_node(aTHX_ 1, NULL);
        }
        /* These OPs produce exactly one item in constructor list context. */
        switch (child->op_type) {
            case OP_CONST:
            case OP_PADSV:
            case OP_RV2SV:
            case OP_UNDEF:
            case OP_ANONLIST:
            case OP_ANONHASH:
                break;
            default:
                return validation_node(aTHX_ 1, NULL);
        }
        value = structure_node(aTHX_ child, depth + 1);
        if (key)
            hv_store_ent((HV *)SvRV(payload), key, SvREFCNT_inc(value), 0);
        else
            av_push((AV *)SvRV(payload), SvREFCNT_inc(value));
        child = OpSIBLING(child);
    }
    return validation_node(aTHX_ op->op_type == OP_ANONLIST ? 2 : 3, payload);
}

static OP *
validate_call(pTHX_ OP *op, GV *namegv, SV *validator)
{
    OP *first, *arg;
    SV *value;
    op = ck_entersub_args_proto(aTHX_ op, namegv,
                               sv_2mortal(newSVpvs("$")));
    first = cUNOPx(op)->op_first;
    if (!OpHAS_SIBLING(first)) first = cUNOPx(first)->op_first;
    arg = OpSIBLING(first);
    if (arg && OpHAS_SIBLING(arg)) {
        dSP;
        ENTER;
        SAVETMPS;
        value = literal_value(aTHX_ arg, 0);
        if (!value)
            value = structure_node(aTHX_ arg, 0);
        else
            value = validation_node(aTHX_ 0, value);

        save_scalar(PL_errgv);
        PUSHMARK(SP);
        XPUSHs(value);
        XPUSHs(&PL_sv_yes);
        PUTBACK;
        call_sv(validator, G_DISCARD | G_EVAL);
        if (SvTRUE(ERRSV))
            croak("Compile-time type error at %s line %" IVdf ": %s",
                  CopFILE(PL_curcop), (IV)CopLINE(PL_curcop), SvPV_nolen(ERRSV));
        FREETMPS;
        LEAVE;
    }
    return op;
}
#endif

#if PERL_VERSION >= 22
static Perl_check_t previous_shape_checker;

static OP *
shape_call(pTHX_ OP *op)
{
    OP *first, *receiver, *method, *arg;
    HV *stash;
    SV **entry;
    HE *signature;
    AV *validators;
    SSize_t index = 0;
    op = previous_shape_checker(aTHX_ op);
    if (op->op_type != OP_ENTERSUB || !(op->op_flags & OPf_KIDS)) return op;
    first = cUNOPx(op)->op_first;
    if (!OpHAS_SIBLING(first)) first = cUNOPx(first)->op_first;
    receiver = OpSIBLING(first);
    if (!receiver || receiver->op_type != OP_PADSV) return op;
    stash = PAD_COMPNAME_TYPE(receiver->op_targ);
    if (!stash) return op;
    entry = hv_fetchs(stash, "__PACKAGE_PROTOTYPE_METHODS", 0);
    if (!entry || !isGV(*entry) || !GvHV(*entry)) return op;
    method = receiver;
    while (OpHAS_SIBLING(method)) method = OpSIBLING(method);
    if (method->op_type != OP_METHOD_NAMED) return op;
    signature = hv_fetch_ent(GvHV(*entry), cMETHOPx_meth(method), 0, 0);
    if (!signature) return op; /* Unlisted methods remain dynamic. */
    if (!IsArrayRef(HeVAL(signature))) return op;
    validators = (AV *)SvRV(HeVAL(signature));

    /* Do not map positional constraints across a potentially expanding list. */
    for (arg = OpSIBLING(receiver); arg != method; arg = OpSIBLING(arg)) {
        if (!arg) return op;
        switch (arg->op_type) {
            case OP_CONST:
            case OP_PADSV:
            case OP_UNDEF:
            case OP_ANONLIST:
            case OP_ANONHASH:
                break;
            default:
                return op;
        }
        index++;
    }
    if (index != av_len(validators) + 1)
        croak("Compile-time arity error for %s at %s line %" IVdf,
              SvPV_nolen(cMETHOPx_meth(method)), CopFILE(PL_curcop),
              (IV)CopLINE(PL_curcop));
    index = 0;
    for (arg = OpSIBLING(receiver); arg != method; arg = OpSIBLING(arg)) {
        SV *value;
        SV **validator = av_fetch(validators, index++, 0);
        dSP;
        if (!validator || !IsCodeRef(*validator)) continue;

        ENTER;
        SAVETMPS;
        value = literal_value(aTHX_ arg, 0);
        if (!value)
            value = structure_node(aTHX_ arg, 0);
        else
            value = validation_node(aTHX_ 0, value);

        save_scalar(PL_errgv);
        PUSHMARK(SP);
        XPUSHs(value);
        XPUSHs(&PL_sv_yes);
        PUTBACK;
        call_sv(*validator, G_DISCARD | G_EVAL);
        if (SvTRUE(ERRSV))
            croak("Compile-time type error at %s line %" IVdf ": %s",
                  CopFILE(PL_curcop), (IV)CopLINE(PL_curcop), SvPV_nolen(ERRSV));

        FREETMPS;
        LEAVE;
    }
    return op;
}
#endif

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
    hv_name_set(stash, pkg, pkglen, pkgsv && SvUTF8(pkgsv) ? SVf_UTF8 : 0);

    {
        HV *metadata = (HV *)sv_2mortal((SV *)newHV());
        sv_magicext((SV *)stash, (SV *)metadata, PERL_MAGIC_ext, &object_vtbl, NULL, 0);
    }
    install_prototype_method(aTHX_ stash);

    HV *hv = (HV *)SvRV(ref);
    hv_iterinit(hv);
    while ((entry = hv_iternext(hv)) != NULL){
        I32 keylen;
        char* key = hv_iterkey(entry, &keylen);
        if (0 < keylen && key[0] != '_') {
            SV *method = hv_iterkeysv(entry);
            SV *val = hv_delete_ent(hv, method, 0, 0);
            CV *cv = IsCodeRef(val) ? (CV *)SvREFCNT_inc(SvRV(val)) : make_closure(aTHX_ val);
            add_method_sv(aTHX_ stash, method, cv);
        }
    }

    ST(0) = sv_bless(ref, stash);
    XSRETURN(1);
}

void
_install_checker(code, validator)
    SV *code
    SV *validator
CODE:
#if PERL_VERSION >= 16
    if (!IsCodeRef(code) || !IsCodeRef(validator))
        croak("Expected code references");
    cv_set_call_checker((CV *)SvRV(code), validate_call, validator);
#else
    croak("Package::Prototype::Typed requires Perl 5.16 or later");
#endif

void
_enable_shape_checker()
CODE:
#if PERL_VERSION >= 22
    wrap_op_checker(OP_ENTERSUB, shape_call, &previous_shape_checker);
#else
    croak("Package::Prototype::Shape requires Perl 5.22 or later");
#endif

SV *
_metadata(object)
    SV *object
CODE:
    RETVAL = newRV_inc((SV *)object_metadata(aTHX_ object));
OUTPUT:
    RETVAL

void
_annotate_accessor(code, info)
    SV *code
    SV *info
CODE:
    if (!IsCodeRef(code) || !IsHashRef(info)) croak("Expected accessor code and metadata");
    sv_magicext(SvRV(code), SvRV(info), PERL_MAGIC_ext, &accessor_vtbl, NULL, 0);

SV *
_members(object)
    SV *object
PREINIT:
    HV *stash;
    HV *members;
    HE *entry;
CODE:
    object_metadata(aTHX_ object);
    stash = SvSTASH(SvRV(object));
    members = (HV *)sv_2mortal((SV *)newHV());
    hv_iterinit(stash);
    while ((entry = hv_iternext(stash))) {
        SV *value = HeVAL(entry);
        CV *code;
        MAGIC *accessor;
        HV *info;
        HE *field;
        if (!isGV(value) || GvCVGEN((GV *)value) || !(code = GvCV((GV *)value))) continue;
        if (CvISXSUB(code) && CvXSUB(code) == XS_prototype_method) continue;
        info = (HV *)sv_2mortal((SV *)newHV());
        accessor = mg_findext((SV *)code, PERL_MAGIC_ext, &accessor_vtbl);
        if (accessor) {
            hv_iterinit((HV *)accessor->mg_obj);
            while ((field = hv_iternext((HV *)accessor->mg_obj)))
                hv_store_ent(info, hv_iterkeysv(field), newSVsv(HeVAL(field)), 0);
        } else {
            MAGIC *getter = mg_findext((SV *)code, PERL_MAGIC_ext, &getter_vtbl);
            hv_store(info, "kind", 4, newSVpv(getter ? "value" : "method", 0), 0);
        }
        {
            HV *owner = stash;
            I32 depth = 0;
            while (1) {
                HV *owner_meta = stash_metadata(aTHX_ owner);
                SV **parent;
                if (!owner_meta) croak("Prototype parent has been reblessed");
                if (!hv_exists_ent(inherited_members(aTHX_ owner_meta), hv_iterkeysv(entry), 0)) break;
                parent = hv_fetch(owner_meta, "parent", 6, 0);
                if (!parent) break;
                owner = SvSTASH(SvRV(*parent));
                depth++;
            }
            hv_store(info, "own", 3, newSViv(depth == 0), 0);
            hv_store(info, "depth", 5, newSViv(depth), 0);
        }
        hv_store_ent(members, hv_iterkeysv(entry), newRV_inc((SV *)info), 0);
    }
    RETVAL = newRV_inc((SV *)members);
OUTPUT:
    RETVAL

void
_link_parent(child, parent)
    SV *child
    SV *parent
PREINIT:
    HV *child_meta, *parent_meta, *child_stash, *parent_stash;
    SV **entry;
    AV *children, *live;
    HE *member;
    I32 i, depth;
    SV *ancestor;
CODE:
    child_meta = object_metadata(aTHX_ child);
    parent_meta = object_metadata(aTHX_ parent);
    if (hv_exists(child_meta, "parent", 6)) croak("Parent already set");
    ancestor = parent;
    for (depth = 0; ; depth++) {
        if (SvRV(ancestor) == SvRV(child)) croak("Prototype cycle");
        if (depth >= 256) croak("Prototype chain exceeds 256 parent links");
        entry = hv_fetch(object_metadata(aTHX_ ancestor), "parent", 6, 0);
        if (!entry) break;
        ancestor = *entry;
    }
    hv_store(child_meta, "parent", 6, newSVsv(parent), 0);
    /* Keep only live weak links when adding another child. */
    live = (AV *)sv_2mortal((SV *)newAV());
    entry = hv_fetch(parent_meta, "children", 8, 0);
    if (entry) {
        children = (AV *)SvRV(*entry);
        for (i = 0; i <= av_len(children); i++) {
            SV **existing = av_fetch(children, i, 0);
            if (existing && SvROK(*existing)) {
                SV *weak = newSVsv(*existing);
                sv_rvweaken(weak);
                av_push(live, weak);
            }
        }
    }
    {
        SV *weak = newSVsv(child);
        sv_rvweaken(weak);
        av_push(live, weak);
    }
    hv_store(parent_meta, "children", 8, newRV_inc((SV *)live), 0);
    child_stash = SvSTASH(SvRV(child));
    parent_stash = SvSTASH(SvRV(parent));
    hv_iterinit(parent_stash);
    while ((member = hv_iternext(parent_stash))) {
        SV *value = HeVAL(member);
        SV *name = hv_iterkeysv(member);
        CV *code;
        if (!isGV(value) || GvCVGEN((GV *)value) || !(code = GvCV((GV *)value))) continue;
        if (CvISXSUB(code) && CvXSUB(code) == XS_prototype_method) continue;
        if (has_member(aTHX_ child_stash, name)) continue;
        install_method(aTHX_ child_stash, name, (CV *)SvREFCNT_inc((SV *)code), 0);
    }

SV *
_accessor_metadata(object)
    SV *object
PREINIT:
    HV *metadata;
CODE:
    metadata = SvROK(object) && SvOBJECT(SvRV(object))
        ? stash_metadata(aTHX_ SvSTASH(SvRV(object))) : NULL;
    RETVAL = metadata ? newRV_inc((SV *)metadata) : newSV(0);
OUTPUT:
    RETVAL
