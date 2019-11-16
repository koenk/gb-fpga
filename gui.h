#ifndef GUI_H
#define GUI_H

#include <stdint.h>
#include <stdbool.h>

struct gui_input {
    bool button_left;
    bool button_right;
    bool button_up;
    bool button_down;
    bool button_a;
    bool button_b;
    bool button_start;
    bool button_select;

    bool special_quit;
    bool special_pause;
};

int gui_init(int width, int height, int zoom, const char *wintitle);
void gui_render_frame(uint8_t *pixbuf);
int gui_input_poll(struct gui_input *input);

#endif
