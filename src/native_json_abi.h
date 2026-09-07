/* Versioned internal native support ABI. Schemas and inputs are borrowed for one call. */
typedef struct { void *(*allocate)(size_t);void *(*reallocate)(void *,size_t);void (*release)(void *); } NativeJsonAllocator;
typedef struct {
    const char *name;unsigned kind;size_t count;const size_t *children;
    const char *const *names;size_t key;unsigned flags;
} NativeJsonShape;
typedef struct { const NativeJsonShape *shapes;size_t count,type,limit; } NativeJsonRequest;
typedef struct { const unsigned char *bytes;size_t length;const MylangHostNode *nodes;size_t count; } NativeJsonInput;
typedef struct { void *data;size_t count;uint64_t work; } NativeJsonOutput;
extern int mylang_native_json_document_v1(const NativeJsonAllocator *,const unsigned char *,size_t,int64_t **,size_t *);
extern int mylang_native_json_encode_v1(const NativeJsonAllocator *,const NativeJsonRequest *,const NativeJsonInput *,NativeJsonOutput *);
extern int mylang_native_json_decode_v1(const NativeJsonAllocator *,const NativeJsonRequest *,const NativeJsonInput *,NativeJsonOutput *);
