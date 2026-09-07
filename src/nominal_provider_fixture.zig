//! Deterministic resource provider for symbolic nominal contract acceptance.
const std = @import("std");
const resources = @import("external_resources.zig");
const external = @import("external_capabilities.zig");
/// Named fields are deliberately reordered to test semantic contract matching.
pub const declarations = "resource File:filesystem;result Open<T:copy>{err:i64,ok:File}" ++
    "struct Failure<T:copy>{code:i64,resource:File}result Finish<T:copy>{err:Failure<T>,ok:bool}" ++
    "struct Chunk<T:copy>{eof:bool,bytes:[4]u8,length:u64}result Read<T:copy>{err:i64,ok:Chunk<T>}" ++
    "struct Progress<T:copy>{eof:bool,length:u64}result Slice<T:copy>{ok:Progress<T>,err:i64}" ++
    "result Written<T:copy>{err:i64,ok:u64}result Status<T:copy>{ok:i64,err:i64}" ++
    "fn singleton<T:copy>(x:T)->[1]T{return new [1]T[x];}";
/// Observable ownership and callback accounting, including failed completion retries.
pub const Counts = struct { acquired: usize = 0, live: usize = 0, completed: usize = 0, released: usize = 0, completions: usize = 0, reads: usize = 0, writes: usize = 0 };
/// Host functions check exact requests and record every byte supplied by the guest.
pub const Fake = struct {
    counts: Counts = .{},
    fail_completion: bool = true,
    failure: ?external.CallError = null,
    written: [8]u8 = @splat(0),
    written_length: usize = 0,
    fn acquire(context: *anyopaque, request: []const u8, _: resources.Permissions) external.CallError!u64 {
        const self: *Fake = @ptrCast(@alignCast(context));
        if (!std.mem.eql(u8, request, &.{42})) return error.Denied;
        self.counts.acquired += 1;
        self.counts.live += 1;
        return self.counts.acquired;
    }
    fn read(context: *anyopaque, _: u64, output: []u8) external.CallError!resources.Read {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.counts.reads += 1;
        @memset(output, 99);
        if (self.failure) |err| return err;
        const length = @min(2, output.len);
        for (output[0..length], 0..) |*byte, index| byte.* = @intCast(7 + index);
        return .{ .length = length, .eof = true };
    }
    fn write(context: *anyopaque, _: u64, input: []const u8) external.CallError!usize {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.counts.writes += 1;
        if (self.failure) |err| return err;
        if (input.len > self.written.len - self.written_length) return error.Failed;
        @memcpy(self.written[self.written_length..][0..input.len], input);
        self.written_length += input.len;
        return input.len;
    }
    fn complete(context: *anyopaque, _: u64) external.CallError!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.counts.completions += 1;
        if (self.fail_completion) {
            self.fail_completion = false;
            return error.Failed;
        }
        self.counts.completed += 1;
        self.counts.live -= 1;
    }
    fn release(context: *anyopaque, _: u64) void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.counts.released += 1;
        self.counts.live -= 1;
    }
    /// Bind this fixture's state to the ordinary typed resource interface.
    pub fn provider(self: *Fake) resources.Provider {
        return .{ .context = self, .acquire = acquire, .read = read, .write = write, .complete = complete, .release = release };
    }
};
/// Exercise ordinary and slice I/O before returning completion ownership for a retry.
pub const program = declarations ++
    "fn finish<T:copy>(file:File)->Finish<T>{match complete_resource<Finish<T>>(file){Finish<T>.ok(done)=>{return new Finish<T>.ok(done);}," ++
    "Finish<T>.err(failure)=>{if read_field(failure,code)==3{return complete_resource<Finish<T>>(failure.resource);}return new Finish<T>.err(failure);}}}" ++
    "fn work<T:copy>(fs:filesystem_cap)->Status<T>{let mut file=try acquire_resource<Open<T>>(fs,singleton::<u8>(42u8));" ++
    "let chunk=try read_resource<Read<T>>(file);let n=try write_resource<Written<T>>(file,singleton::<u8>(9u8));" ++
    "let mut bytes=new [3]u8[1u8,2u8,3u8];let before=bytes;let mut length=0u64;" ++
    "borrow mut bytes[0..3] as out{let progress=try read_resource_slice<Slice<T>>(file,out);length=progress.length;if !progress.eof{return new Status<T>.err(90);}}" ++
    "borrow bytes[0..length] as input{discard try write_resource_slice<Written<T>>(file,input);}" ++
    "match finish::<T>(file){Finish<T>.ok(done)=>{if !done{return new Status<T>.err(91);}},Finish<T>.err(failure)=>{return new Status<T>.err(failure.code);}}" ++
    "if !chunk.eof{return new Status<T>.err(92);}return new Status<T>.ok(cast<i64>(chunk.length)+cast<i64>(chunk.bytes[0])+cast<i64>(chunk.bytes[1])+" ++
    "cast<i64>(chunk.bytes[2])+cast<i64>(chunk.bytes[3])+cast<i64>(n)+cast<i64>(bytes[0])+cast<i64>(bytes[1])+cast<i64>(bytes[2])+cast<i64>(before[0]));}" ++
    "fn main(fs:filesystem_cap)->i64{match work::<bool>(fs){Status<bool>.ok(n)=>{return n;},Status<bool>.err(e)=>{return -e;}}}";
