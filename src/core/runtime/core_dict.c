/* S2-D runtime dispatch placeholder. Concatenated after core_rt.c by driver.zig. */
void myl_core_s2_unsupported(int operation) {
    fprintf(stderr, "error[E_CORE_UNSUPPORTED]: S2 IR operation %d is not implemented\n", operation);
    os_exit(1);
}
