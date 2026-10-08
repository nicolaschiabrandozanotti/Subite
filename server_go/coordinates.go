package main

import (
	"encoding/json"
	"fmt"
	"math"
	"strconv"
)

type coordinate float64

func (c *coordinate) UnmarshalJSON(raw []byte) error {
	var number float64
	if len(raw) > 0 && raw[0] == '"' {
		var text string
		if err := json.Unmarshal(raw, &text); err != nil {
			return err
		}
		value, err := strconv.ParseFloat(text, 64)
		if err != nil {
			return err
		}
		number = value
	} else {
		if string(raw) == "null" {
			return fmt.Errorf("missing coordinate")
		}
		if err := json.Unmarshal(raw, &number); err != nil {
			return err
		}
	}
	if math.IsNaN(number) || math.IsInf(number, 0) {
		return fmt.Errorf("invalid coordinate")
	}
	*c = coordinate(number)
	return nil
}
