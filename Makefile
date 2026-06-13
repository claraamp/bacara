MCU     = atmega328p
F_CPU   = 16000000UL
CC      = avr-gcc
OBJCOPY = avr-objcopy
CFLAGS  = -mmcu=$(MCU) -DF_CPU=$(F_CPU) -Os -Wall -I src
TARGET  = bacara

SRCS = src/main.S \
       src/display.S \
       src/interrupts.S \
       src/game.S \
       src/lcd_direto.c

OBJS = $(SRCS:.S=.o)
OBJS := $(OBJS:.c=.o)

all: $(TARGET).hex

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET).elf: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O ihex $< $@

clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).hex

.PHONY: all clean
