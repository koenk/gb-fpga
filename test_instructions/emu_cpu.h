#ifndef EMUCPU_H
#define EMUCPU_H

#include "common.h"

void ecpu_init(void);
void ecpu_reset(struct state *state);
void ecpu_get_state(struct state *state);
int ecpu_step(void);

#endif
