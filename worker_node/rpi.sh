#! /bin/bash

# DOCS https://docs.radxa.com/en/x/x4/software/flash?flash_way=Software
sudo gpioset gpiochip0 17=1
sudo gpioset gpiochip0 7=1

sleep 1

sudo gpioset gpiochip0 17=0
sudo gpioset gpiochip0 7=0

