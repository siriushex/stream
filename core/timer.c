/*
 * Astra Core
 * http://cesbo.com/astra
 *
 * Copyright (C) 2012-2015, Andrey Dyldin <and@cesbo.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "clock.h"
#include "timer.h"
#include "loopctl.h"

struct asc_timer_t
{
    timer_callback_t callback;
    void *arg;

    uint64_t interval;
    uint64_t next_shot;

    size_t heap_index;
    bool active;
    bool in_callback;
    bool free_after_callback;
};

static asc_timer_t **timer_heap = NULL;
static size_t timer_heap_size = 0;
static size_t timer_heap_cap = 0;
static uint64_t timer_next_due = 0;

static void timer_update_next_due(void)
{
    timer_next_due = (timer_heap_size > 0) ? timer_heap[0]->next_shot : 0;
}

static void timer_heap_swap(size_t a, size_t b)
{
    asc_timer_t *left = timer_heap[a];
    asc_timer_t *right = timer_heap[b];
    timer_heap[a] = right;
    timer_heap[b] = left;
    right->heap_index = a;
    left->heap_index = b;
}

static void timer_heap_sift_up(size_t index)
{
    while(index > 0)
    {
        const size_t parent = (index - 1) / 2;
        if(timer_heap[parent]->next_shot <= timer_heap[index]->next_shot)
            break;
        timer_heap_swap(parent, index);
        index = parent;
    }
}

static void timer_heap_sift_down(size_t index)
{
    while(true)
    {
        size_t left = (index * 2) + 1;
        size_t right = left + 1;
        size_t next = index;

        if(left < timer_heap_size && timer_heap[left]->next_shot < timer_heap[next]->next_shot)
            next = left;
        if(right < timer_heap_size && timer_heap[right]->next_shot < timer_heap[next]->next_shot)
            next = right;
        if(next == index)
            break;

        timer_heap_swap(index, next);
        index = next;
    }
}

static void timer_heap_reserve(size_t required)
{
    if(required <= timer_heap_cap)
        return;

    size_t next_cap = timer_heap_cap ? timer_heap_cap * 2 : 64;
    while(next_cap < required)
        next_cap *= 2;

    asc_timer_t **next_heap = (asc_timer_t **)realloc(timer_heap, next_cap * sizeof(asc_timer_t *));
    if(!next_heap)
        astra_abort();

    timer_heap = next_heap;
    timer_heap_cap = next_cap;
}

static void timer_heap_push(asc_timer_t *timer)
{
    timer_heap_reserve(timer_heap_size + 1);
    timer->heap_index = timer_heap_size;
    timer->active = true;
    timer_heap[timer_heap_size++] = timer;
    timer_heap_sift_up(timer->heap_index);
    timer_update_next_due();
}

static asc_timer_t *timer_heap_remove_at(size_t index)
{
    if(index >= timer_heap_size)
        return NULL;

    asc_timer_t *removed = timer_heap[index];
    const size_t last = timer_heap_size - 1;

    if(index != last)
    {
        timer_heap[index] = timer_heap[last];
        timer_heap[index]->heap_index = index;
    }
    --timer_heap_size;

    if(index < timer_heap_size)
    {
        if(index > 0 && timer_heap[index]->next_shot < timer_heap[(index - 1) / 2]->next_shot)
            timer_heap_sift_up(index);
        else
            timer_heap_sift_down(index);
    }

    removed->heap_index = 0;
    removed->active = false;
    timer_update_next_due();
    return removed;
}

void asc_timer_core_init(void)
{
    timer_heap = NULL;
    timer_heap_size = 0;
    timer_heap_cap = 0;
    timer_next_due = 0;
}

void asc_timer_core_destroy(void)
{
    while(timer_heap_size > 0)
    {
        asc_timer_t *timer = timer_heap_remove_at(0);
        if(timer)
            free(timer);
    }
    free(timer_heap);
    timer_heap = NULL;
    timer_heap_cap = 0;
    timer_next_due = 0;
}

void asc_timer_core_loop(void)
{
    const uint64_t cur = asc_utime();
    if(timer_next_due != 0 && cur < timer_next_due)
        return;

    while(timer_heap_size > 0)
    {
        const uint64_t now = asc_utime();
        asc_timer_t *timer = timer_heap[0];
        if(now < timer->next_shot)
            break;

        timer = timer_heap_remove_at(0);
        if(!timer)
            continue;

        if(!timer->callback)
        {
            free(timer);
            continue;
        }

        is_main_loop_idle = false;
        timer->in_callback = true;

        if(timer->interval == 0)
        {
            // one shot timer
            timer->callback(timer->arg);
            timer->in_callback = false;
            free(timer);
            continue;
        }

        timer->next_shot = now + timer->interval;
        timer->callback(timer->arg);
        timer->in_callback = false;

        if(timer->free_after_callback || !timer->callback)
            free(timer);
        else
            timer_heap_push(timer);
    }
}

asc_timer_t * asc_timer_init(unsigned int ms, void (*callback)(void *), void *arg)
{
    asc_timer_t *const timer = (asc_timer_t *)calloc(1, sizeof(asc_timer_t));
    timer->interval = ms * 1000;
    timer->callback = callback;
    timer->arg = arg;

    timer->next_shot = asc_utime() + timer->interval;

    timer_heap_push(timer);

    return timer;
}

asc_timer_t * asc_timer_one_shot(unsigned int ms, void (*callback)(void *), void *arg)
{
    asc_timer_t *const timer = asc_timer_init(ms, callback, arg);
    timer->interval = 0;

    return timer;
}

void asc_timer_destroy(asc_timer_t *timer)
{
    if(!timer)
        return;

    timer->callback = NULL;
    if(timer->active)
        timer_heap_remove_at(timer->heap_index);

    if(timer->in_callback)
    {
        timer->free_after_callback = true;
        return;
    }

    free(timer);
}
