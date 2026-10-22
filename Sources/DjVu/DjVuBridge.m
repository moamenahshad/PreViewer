#import "DjVuBridge.h"
#include "ddjvuapi.h"
#include "miniexp.h"
#include <unistd.h>
#include <stdatomic.h>
@implementation DPCancellation { atomic_bool _cancelled; }
- (BOOL)cancelled { return atomic_load(&_cancelled); }
- (void)cancel { atomic_store(&_cancelled, true); }
@end

static id expression(miniexp_t e, int depth) {
    if (depth > 64 || e == miniexp_dummy) return @[];
    if (miniexp_numberp(e)) return @(miniexp_to_int(e));
    if (miniexp_stringp(e)) return @(miniexp_to_str(e));
    if (miniexp_symbolp(e)) { const char *n = miniexp_to_name(e); return n ? @(n) : @""; }
    NSMutableArray *a = [NSMutableArray new];
    for (int n = 0; miniexp_consp(e) && n < 100000; e = miniexp_cdr(e), n++) [a addObject:expression(miniexp_car(e), depth+1)];
    return a;
}
@implementation DPDecoder {
    ddjvu_context_t *_context;
    ddjvu_document_t *_document;
    NSString *_failure;
}
- (void)drain {
    ddjvu_message_t *m;
    while ((m = ddjvu_message_peek(_context))) {
        if (m->m_any.tag == DDJVU_ERROR) _failure = @(m->m_error.message);
        ddjvu_message_pop(_context);
    }
}
- (BOOL)fail:(NSError **)error message:(NSString *)message {
    if (error) *error = [NSError errorWithDomain:@"DjVuPreview.Decoder" code:1 userInfo:@{NSLocalizedDescriptionKey:_failure ?: message}];
    return NO;
}
- (instancetype)initWithURL:(NSURL *)url cancellation:(DPCancellation *)cancellation error:(NSError **)error {
    if (!(self = [super init])) return nil;
    _cancellation = cancellation;
    _context = ddjvu_context_create("PreViewer");
    ddjvu_cache_set_size(_context, 24*1024*1024);
    _document = ddjvu_document_create_by_filename_utf8(_context, url.fileSystemRepresentation, 0);
    if (!_document) { [self fail:error message:@"Unable to open the DjVu document."]; return nil; }
    double deadline = CFAbsoluteTimeGetCurrent()+30;
    while (!ddjvu_document_decoding_done(_document) && CFAbsoluteTimeGetCurrent()<deadline && !self.cancellation.cancelled) { [self drain]; usleep(5000); }
    if (self.cancellation.cancelled) {
        [self fail:error message:@"DjVu opening was cancelled."]; return nil;
    }
    if (!ddjvu_document_decoding_done(_document) || ddjvu_document_decoding_error(_document)) {
        [self fail:error message:@"DjVu header decoding failed or timed out."]; return nil;
    }
    return self;
}
- (void)dealloc {
    if (_document) { ddjvu_job_stop(ddjvu_document_job(_document)); ddjvu_document_release(_document); }
    if (_context) ddjvu_context_release(_context);
}
- (NSInteger)pageCount { return ddjvu_document_get_pagenum(_document); }
- (NSString *)version { return @(ddjvu_get_version_string()); }
- (NSDictionary *)pageInfo:(NSInteger)index error:(NSError **)error {
    ddjvu_pageinfo_t info;
    ddjvu_status_t status;
    double deadline = CFAbsoluteTimeGetCurrent()+30;
    while ((status = ddjvu_document_get_pageinfo(_document, (int)index, &info)) < DDJVU_JOB_OK && CFAbsoluteTimeGetCurrent()<deadline && !self.cancellation.cancelled) { [self drain]; usleep(5000); }
    if (status != DDJVU_JOB_OK) { [self fail:error message:@"Unable to read page dimensions."]; return nil; }
    if (info.rotation & 1) { int swap = info.width; info.width = info.height; info.height = swap; }
    return @{@"width":@(info.width), @"height":@(info.height), @"dpi":@(info.dpi), @"rotation":@(info.rotation)};
}
- (NSDictionary *)render:(NSInteger)index maximumDimension:(NSInteger)limit cancellation:(DPCancellation *)request error:(NSError **)error {
    ddjvu_page_t *page = ddjvu_page_create_by_pageno(_document, (int)index);
    if (!page) { [self fail:error message:@"Unable to decode this page."]; return nil; }
    double deadline = CFAbsoluteTimeGetCurrent()+45;
    while (!ddjvu_page_decoding_done(page) && CFAbsoluteTimeGetCurrent()<deadline && !self.cancellation.cancelled && !request.cancelled) { [self drain]; usleep(5000); }
    if (request.cancelled || self.cancellation.cancelled || !ddjvu_page_decoding_done(page) || ddjvu_page_decoding_error(page)) {
        ddjvu_job_stop(ddjvu_page_job(page)); ddjvu_page_release(page);
        [self fail:error message:@"Page decoding failed or timed out."]; return nil;
    }
    // Work in unrotated source coordinates; Swift applies the source orientation consistently to text and image.
    ddjvu_page_set_rotation(page, DDJVU_ROTATE_0);
    int w = ddjvu_page_get_width(page), h = ddjvu_page_get_height(page);
    double factor = MIN(1.0, (double)limit/MAX(w,h));
    w = MAX(1,(int)ceil(w*factor)); h = MAX(1,(int)ceil(h*factor));
    if ((uint64_t)w*h > 40000000) { ddjvu_page_release(page); [self fail:error message:@"This page exceeds the 40 megapixel safety limit. Select a lower resolution."]; return nil; }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)w*h*3];
    ddjvu_format_t *format = ddjvu_format_create(DDJVU_FORMAT_RGB24, 0, NULL);
    ddjvu_format_set_row_order(format, 1); ddjvu_format_set_y_direction(format, 1);
    ddjvu_rect_t rect = {0,0,w,h};
    BOOL ok = ddjvu_page_render(page, DDJVU_RENDER_COLOR, &rect, &rect, format, w*3, data.mutableBytes);
    ddjvu_format_release(format); ddjvu_page_release(page);
    if (!ok) { [self fail:error message:@"Unable to render the DjVu page."]; return nil; }
    return @{@"data":data,@"width":@(w),@"height":@(h)};
}
- (NSArray *)text:(NSInteger)index cancellation:(DPCancellation *)request error:(NSError **)error {
    miniexp_t e; double deadline = CFAbsoluteTimeGetCurrent()+30;
    while ((e = ddjvu_document_get_pagetext(_document,(int)index,"word")) == miniexp_dummy && CFAbsoluteTimeGetCurrent()<deadline && !self.cancellation.cancelled && !request.cancelled) { [self drain]; usleep(5000); }
    if (e == miniexp_dummy || !miniexp_listp(e) || request.cancelled || self.cancellation.cancelled) {
        if (e != miniexp_dummy) ddjvu_miniexp_release(_document,e);
        [self fail:error message:@"The source text could not be read. Try again, or disable text preservation to export images only."];
        return nil;
    }
    id result = expression(e,0); ddjvu_miniexp_release(_document,e);
    return [result isKindOfClass:NSArray.class] ? result : @[];
}
- (NSArray *)outline {
    miniexp_t e = miniexp_dummy;
    double deadline = CFAbsoluteTimeGetCurrent()+30;
    while (e == miniexp_dummy && CFAbsoluteTimeGetCurrent()<deadline && !self.cancellation.cancelled) {
        e = ddjvu_document_get_outline(_document);
        if (e == miniexp_dummy) { [self drain]; usleep(5000); }
    }
    if (e == miniexp_dummy || self.cancellation.cancelled) return @[];
    id result = expression(e,0); ddjvu_miniexp_release(_document,e);
    return [result isKindOfClass:NSArray.class] ? result : @[];
}
- (NSDictionary *)metadata {
    NSMutableDictionary *result = [NSMutableDictionary new];
    for (int attempt=0; attempt<2 && !result.count && !self.cancellation.cancelled; attempt++) {
        miniexp_t e; double deadline = CFAbsoluteTimeGetCurrent()+10;
        do {
            e = attempt == 0 ? ddjvu_document_get_anno(_document,1) : ddjvu_document_get_pageanno(_document,0);
            if (e == miniexp_dummy) { [self drain]; usleep(5000); }
        } while (e == miniexp_dummy && CFAbsoluteTimeGetCurrent()<deadline && !self.cancellation.cancelled);
        if (e != miniexp_dummy) {
            miniexp_t *keys = ddjvu_anno_get_metadata_keys(e);
            if (keys) { for (int i=0; keys[i]; i++) {
                const char *value = ddjvu_anno_get_metadata(e,keys[i]);
                if (value) result[@(miniexp_to_name(keys[i]))] = @(value);
            } free(keys); }
            ddjvu_miniexp_release(_document,e);
        }
    }
    return result;
}
@end
