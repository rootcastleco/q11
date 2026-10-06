/* Bounded ext4 label/UUID reader for initramfs. No writes, mounts or NAND access.
 * Build: arm-linux-gnueabihf-gcc -static -Os -Wall -Wextra -Werror
 *        -o q11-root-probe root_probe.c
 * --image permits regular-file fixtures on a lab host; normal mode requires
 * an external sd/mmc block device. It deliberately does not inspect MTD.
 */
#define _POSIX_C_SOURCE 200809L
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char **argv) {
    int image = argc == 3 && strcmp(argv[1], "--image") == 0;
    if (argc == 2 && strcmp(argv[1], "--help") == 0) {
        puts("Usage: q11-root-probe /dev/sdXN|/dev/mmcblkXpY\n       q11-root-probe --image regular.ext4");
        return 0;
    }
    if ((!image && argc != 2) || (image && argc != 3)) {
        fputs("invalid arguments; use --help\n", stderr); return 2;
    }
    const char *path = argv[image ? 2 : 1];
    if (!image && (strchr(path, '\n') || (strncmp(path, "/dev/sd", 7) != 0 && strncmp(path, "/dev/mmcblk", 11) != 0))) {
        fputs("external block device required\n", stderr); return 2;
    }
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) { perror("open"); return 2; }
    struct stat info;
    if (fstat(fd, &info) < 0 || (image ? !S_ISREG(info.st_mode) : !S_ISBLK(info.st_mode))) {
        fputs("incorrect input type\n", stderr); close(fd); return 2;
    }
    unsigned char super[256];
    ssize_t got = pread(fd, super, sizeof(super), 1024);
    close(fd);
    if (got != (ssize_t)sizeof(super) || super[56] != 0x53 || super[57] != 0xef) {
        fputs("not an ext filesystem superblock\n", stderr); return 2;
    }
    char label[17];
    memcpy(label, super + 120, 16); label[16] = '\0';
    for (unsigned int i = 0; i < 16 && label[i]; ++i) {
        if ((unsigned char)label[i] < 32 || label[i] == '"' || label[i] == '\\') {
            fputs("unsupported label characters\n", stderr); return 2;
        }
    }
    printf("UUID=\"");
    for (unsigned int i = 0; i < 16; ++i) {
        if (i == 4 || i == 6 || i == 8 || i == 10) putchar('-');
        printf("%02x", super[104 + i]);
    }
    printf("\" LABEL=\"%s\"\n", label);
    return 0;
}
