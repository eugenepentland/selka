#include "native_text_methods.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
void myl_qbe_fail(void *context,const char *code) {
    (void)context; (void)code;
    assert(0 && "unexpected text trap");
}
/* Every temporary this test builds is retained here, so collection stress never
   reclaims an operand that is still an argument of the expression under test. */
static myl_native_list *bag;
static myl_native_text *raw(myl_native_heap *heap,const char *text) {
    myl_native_text *value=myl_native_text_from_utf8(heap,(const unsigned char *)text,strlen(text));
    assert(value);
    myl_native_root root;
    myl_native_root_push(heap,&root,&value,&pointer);
    assert(myl_native_list_append(heap,bag,&value));
    myl_native_root_pop(heap,&root);
    return value;
}
static void equals(myl_native_text *value,const char *text) {
    assert(value);
    unsigned char frame[64];
    size_t written=myl_native_text_utf8(value,frame,sizeof frame);
    assert(written<=sizeof frame);
    assert(written==strlen(text));
    assert(!written || !memcmp(frame,text,written));
}
static void keep(myl_native_heap *heap,myl_native_text *value) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&value,&pointer);
    assert(myl_native_list_append(heap,bag,&value));
    myl_native_root_pop(heap,&root);
}
static size_t find(const char *haystack,const char *needle) {
    return myl_native_octets_find((const unsigned char *)haystack,strlen(haystack),(const unsigned char *)needle,strlen(needle));
}
static size_t tally(const char *haystack,const char *needle) {
    return myl_native_octets_count((const unsigned char *)haystack,strlen(haystack),(const unsigned char *)needle,strlen(needle));
}
/* spec-case: TEXT-SCAN-1. The bulk search answers exactly what a comparison at
   every offset answered: the first match, at either end, past any number of
   first-octet candidates that fail (more than the in-place budget hands the rest
   to `memmem`), and non-overlapping counts. */
static void octet_search(void) {
    assert(find("abc","")==0 && find("","")==0);
    assert(find("","a")==SIZE_MAX && find("ab","abc")==SIZE_MAX);
    assert(find("abc","a")==0 && find("abc","c")==2 && find("abc","z")==SIZE_MAX);
    assert(find("abcab","ab")==0 && find("xxab","ab")==2 && find("abc","abc")==0);
    assert(find("aaaaaaaaaaaaaaaaaaaaaab","ab")==21);
    assert(find("aaaaaaaaaaaaaaaaaaaaaaa","aab")==SIZE_MAX);
    assert(find("abababababababababababx","abx")==20);
    assert(find("h\xc3\xa9llo \xc3\xa9","\xc3\xa9 ")==SIZE_MAX && find("h\xc3\xa9llo \xc3\xa9","o \xc3\xa9")==5);
    assert(tally("aaa","aa")==1 && tally("aaaa","aa")==2 && tally("abababa","aba")==2);
    assert(tally("a,b,,c,",",")==4 && tally("",",")==0 && tally("abc","")==0 && tally("ab","abc")==0);
    assert(tally("aaaaaaaaaaaaaaaaaaaaaabaab","aab")==2);
    /* A one-octet tally spans several 64 KiB blocks. */
    static unsigned char large[200001];
    memset(large,'x',sizeof large);
    for (size_t i=0;i<sizeof large;i+=7) large[i]=',';
    assert(myl_native_octets_count(large,sizeof large,(const unsigned char *)",",1)==200001/7+1);
    assert(myl_native_octets_count(large,sizeof large,(const unsigned char *)",x",2)==200001/7+1);
    assert(myl_native_octets_count(large,sizeof large,(const unsigned char *)"x,",2)==200001/7);
    assert(myl_native_octets_find(large+1,sizeof large-1,(const unsigned char *)",",1)==6);
}
static myl_native_list *pieces(myl_native_heap *heap,myl_native_root *root,const char *text,const char *separator) {
    myl_native_list *parts=myl_native_text_split(heap,raw(heap,text),raw(heap,separator));
    assert(parts);
    myl_native_root_push(heap,root,&parts,&pointer);
    return parts;
}
/* spec-case: TEXT-SCAN-3. Separator splits keep every empty piece and the count
   of cuts the list was sized for, and a non-ASCII receiver's pieces measure
   their own scalars. */
static void separator_split(myl_native_heap *heap) {
    myl_native_root root;
    myl_native_list *parts=pieces(heap,&root,"a,b,,c,",",");
    myl_native_text **items=parts->storage;
    assert(parts->length==5 && parts->capacity==5);
    equals(items[0],"a"); equals(items[1],"b"); equals(items[2],""); equals(items[3],"c"); equals(items[4],"");
    myl_native_root_pop(heap,&root);
    parts=pieces(heap,&root,"",",");
    assert(parts->length==1); equals(((myl_native_text **)parts->storage)[0],"");
    myl_native_root_pop(heap,&root);
    parts=pieces(heap,&root,"abc","abcd");
    assert(parts->length==1); equals(((myl_native_text **)parts->storage)[0],"abc");
    myl_native_root_pop(heap,&root);
    parts=pieces(heap,&root,"aaa","aa");
    items=parts->storage;
    assert(parts->length==2); equals(items[0],""); equals(items[1],"a");
    myl_native_root_pop(heap,&root);
    parts=pieces(heap,&root,"aaaaaaaaaaaaaaaaaaaab--c--","--");
    items=parts->storage;
    assert(parts->length==3); equals(items[0],"aaaaaaaaaaaaaaaaaaaab"); equals(items[1],"c"); equals(items[2],"");
    myl_native_root_pop(heap,&root);
    parts=pieces(heap,&root,"\xc3\xa9|\xf0\x9f\x99\x82\xc3\xa9|x","|");
    items=parts->storage;
    assert(parts->length==3);
    assert(items[0]->length==1 && items[1]->length==2 && items[2]->length==1);
    assert(!(items[0]->flags&MYL_TEXT_ASCII) && (items[2]->flags&MYL_TEXT_ASCII));
    equals(items[1],"\xf0\x9f\x99\x82\xc3\xa9");
    myl_native_root_pop(heap,&root);
}
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    myl_native_root roots[2];
    bag=myl_native_list_new(&heap,&pointer,0); assert(bag);
    myl_native_root_push(&heap,&roots[0],&bag,&pointer);
    myl_native_text *padded=raw(&heap,"  value  ");
    equals(myl_native_text_trim(&heap,padded,MYL_TEXT_BOTH),"value");
    equals(myl_native_text_trim(&heap,padded,MYL_TEXT_LEADING),"value  ");
    equals(myl_native_text_trim(&heap,padded,MYL_TEXT_TRAILING),"  value");
    equals(myl_native_text_trim(&heap,raw(&heap,"\t\n\v\f\r x "),MYL_TEXT_BOTH),"x");
    equals(myl_native_text_trim(&heap,raw(&heap,"   "),MYL_TEXT_BOTH),"");
    equals(myl_native_text_trim(&heap,raw(&heap,""),MYL_TEXT_BOTH),"");
    /* Case mapping covers ASCII letters and leaves every other scalar alone. */
    equals(myl_native_text_case(&heap,raw(&heap,"aB\xc3\xa9"),1),"AB\xc3\xa9");
    equals(myl_native_text_case(&heap,raw(&heap,"aB\xc3\xa9"),0),"ab\xc3\xa9");
    equals(myl_native_text_case(&heap,raw(&heap,""),1),"");
    /* zfill keeps a leading sign in front of its padding and never truncates. */
    equals(myl_native_text_zfill(&heap,raw(&heap,"7"),3),"007");
    equals(myl_native_text_zfill(&heap,raw(&heap,"-7"),4),"-007");
    equals(myl_native_text_zfill(&heap,raw(&heap,"+7"),4),"+007");
    equals(myl_native_text_zfill(&heap,raw(&heap,"-"),3),"-00");
    equals(myl_native_text_zfill(&heap,raw(&heap,"1234"),2),"1234");
    equals(myl_native_text_zfill(&heap,raw(&heap,""),3),"000");
    equals(myl_native_text_zfill(&heap,raw(&heap,"7"),-5),"7");
    equals(myl_native_text_zfill(&heap,raw(&heap,""),0),"");
    /* Search answers Python's indices and counts, including for absent needles. */
    myl_native_text *line=raw(&heap,"banana");
    myl_native_text *empty=raw(&heap,"");
    assert(myl_native_text_find(line,raw(&heap,"na"))==2);
    assert(myl_native_text_find(line,raw(&heap,"zz"))==-1);
    assert(myl_native_text_find(line,raw(&heap,"bananas"))==-1);
    assert(myl_native_text_find(line,empty)==-1);
    assert(myl_native_text_count(line,raw(&heap,"na"))==2);
    assert(myl_native_text_count(line,raw(&heap,"ana"))==1);
    assert(myl_native_text_count(empty,raw(&heap,"a"))==0);
    assert(myl_native_text_count(line,empty)==0);
    assert(myl_native_text_edge(line,raw(&heap,"ban"),1));
    assert(myl_native_text_edge(line,raw(&heap,"ana"),0));
    assert(!myl_native_text_edge(line,raw(&heap,"nan"),1));
    assert(myl_native_text_edge(line,empty,1) && myl_native_text_edge(line,empty,0));
    assert(!myl_native_text_edge(empty,line,1));
    /* Classification answers false for empty text, as in Python. */
    assert(myl_native_text_every(raw(&heap,"42"),MYL_TEXT_DIGIT));
    assert(!myl_native_text_every(raw(&heap,"4a"),MYL_TEXT_DIGIT));
    assert(myl_native_text_every(raw(&heap,"abZ"),MYL_TEXT_ALPHA));
    assert(!myl_native_text_every(raw(&heap,"\xc3\xa9"),MYL_TEXT_ALPHA));
    assert(myl_native_text_every(raw(&heap," \t\n\r\v\f"),MYL_TEXT_SPACE));
    assert(!myl_native_text_every(empty,MYL_TEXT_DIGIT));
    assert(!myl_native_text_every(empty,MYL_TEXT_ALPHA));
    assert(!myl_native_text_every(empty,MYL_TEXT_SPACE));
    /* Replacement is non-overlapping and may shrink, grow or empty the text. */
    equals(myl_native_text_replace(&heap,line,raw(&heap,"na"),raw(&heap,"NA")),"baNANA");
    equals(myl_native_text_replace(&heap,raw(&heap,"aaa"),raw(&heap,"aa"),raw(&heap,"b")),"ba");
    equals(myl_native_text_replace(&heap,raw(&heap,"aaa"),raw(&heap,"a"),empty),"");
    equals(myl_native_text_replace(&heap,raw(&heap,"aa"),raw(&heap,"a"),raw(&heap,"bb")),"bbbb");
    equals(myl_native_text_replace(&heap,line,raw(&heap,"zz"),raw(&heap,"y")),"banana");
    equals(myl_native_text_replace(&heap,empty,raw(&heap,"a"),raw(&heap,"b")),"");
    assert(!myl_native_text_replace(&heap,line,empty,raw(&heap,"b")));
    /* Runs between matches are copied whole, matches at either end included,
       and a first octet that recurs without matching changes nothing. */
    equals(myl_native_text_replace(&heap,raw(&heap,"abxab"),raw(&heap,"ab"),empty),"x");
    equals(myl_native_text_replace(&heap,raw(&heap,"aaaaaaaaaaaaaaaaaaaaaab"),raw(&heap,"ab"),raw(&heap,"X")),"aaaaaaaaaaaaaaaaaaaaaX");
    myl_native_text *accented=myl_native_text_replace(&heap,raw(&heap,"h\xc3\xa9llo \xc3\xa9t\xc3\xa9"),raw(&heap,"\xc3\xa9"),raw(&heap,"e"));
    equals(accented,"hello ete");
    assert(accented->length==9);
    myl_native_text *widened=myl_native_text_replace(&heap,raw(&heap,"a-b"),raw(&heap,"-"),raw(&heap,"\xf0\x9f\x99\x82"));
    equals(widened,"a\xf0\x9f\x99\x82" "b");
    assert(widened->length==3 && widened->bytes==6);
    assert(myl_native_text_count(raw(&heap,"h\xc3\xa9llo \xc3\xa9"),raw(&heap,"\xc3\xa9"))==2);
    assert(myl_native_text_count(raw(&heap,"aaaaaaaaaaaaaaaaaaaaaabaab"),raw(&heap,"aab"))==2);
    assert(myl_native_text_find(raw(&heap,"\xc3\xa9t\xc3\xa9"),raw(&heap,"t"))==1);
    octet_search();
    separator_split(&heap);
    /* splitlines drops the terminators and yields no line for empty text. */
    myl_native_list *lines=myl_native_text_lines(&heap,raw(&heap,"a\nb\r\nc\rd"));
    assert(lines && lines->length==4);
    myl_native_root_push(&heap,&roots[1],&lines,&pointer);
    myl_native_text **pieces=lines->storage;
    equals(pieces[0],"a"); equals(pieces[1],"b"); equals(pieces[2],"c"); equals(pieces[3],"d");
    myl_native_list *none=myl_native_text_lines(&heap,empty);
    assert(none && none->length==0);
    myl_native_list *one=myl_native_text_lines(&heap,raw(&heap,"a\n"));
    assert(one && one->length==1);
    myl_native_list *blanks=myl_native_text_lines(&heap,raw(&heap,"\n\n"));
    assert(blanks && blanks->length==2);
    /* The payload is UTF-8 octets, which is exactly what the shared number
       grammar reads. */
    assert(myl_native_text_payload(line)[0]=='b' && line->bytes==strlen("banana"));
    keep(&heap,myl_native_text_trim(&heap,padded,MYL_TEXT_BOTH));
    myl_native_heap_collect(&heap);
    equals(((myl_native_text **)bag->storage)[bag->length-1],"value");
    equals(padded,"  value  ");
    equals(((myl_native_text **)lines->storage)[0],"a");
    for (int i=1;i>=0;--i) assert(myl_native_root_pop(&heap,&roots[i]));
    bag=NULL;
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==0);
    myl_native_heap_destroy(&heap);
    puts("native text method tests passed");
    return 0;
}
