#ifndef VCPU_H
#define VCPU_H

#include "common.h"

void vcpu_init(void);
void vcpu_reset(struct state *state);
void vcpu_get_state(struct state *state);
int vcpu_step(void);

#endif
