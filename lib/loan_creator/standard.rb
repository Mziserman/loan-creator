module LoanCreator
  class Standard < LoanCreator::Common

    def lender_time_table_data(amount)
      defer_r_total_pay  = self.deferred_total_rounded_interests(amount)

      rounded_monthly_payment = self.rounded_monthly_payment(amount)
      total_rounded = self.total_rounded_payment(amount)

      difference = self.financial_diff(self.precise_difference(amount))

      # last payment includes the financial difference
      last_pay = rounded_monthly_payment - difference

      # total payment including the financial difference
      total_pay =
        (total_rounded + defer_r_total_pay - difference).round

      # total interests based on total payment
      total_interests = total_pay - amount.round

      [rounded_monthly_payment, last_pay, total_pay, total_interests]
    end

    def lender_time_table(amount)
      data = lender_time_table_data(amount)
      rounded_monthly_payment = data[0]
      last_payment            = data[1]
      total_payment           = data[2]
      time_table              = []
      remaining_capital       = amount.round
      calc_paid_capital       = 0
      calc_remaining_int      = data[3]
      calc_paid_interests     = 0

      # starts with deferred time tables if any
      defer_r_mth_pay = self.rounded_monthly_interests(amount)

      self.deferred_in_months.times do |term|
        calc_remaining_int  -= defer_r_mth_pay
        calc_paid_interests += defer_r_mth_pay

        time_table << LoanCreator::TimeTable.new(
          term:                            term + 1,
          monthly_payment:                 defer_r_mth_pay,
          monthly_payment_capital_share:   0,
          monthly_payment_interests_share: defer_r_mth_pay,
          remaining_capital:               remaining_capital,
          paid_capital:                    0,
          remaining_interests:             calc_remaining_int,
          paid_interests:                  calc_paid_interests
        )
      end

      # all but last time table terms during normal period
      (self.duration_in_months - 1).times do |term|
        # monthly payment interests share
        calc_monthly_interests =
          (remaining_capital * self.monthly_interests_rate).round

        # monthly payment capital share
        calc_monthly_capital =
          (rounded_monthly_payment - calc_monthly_interests).round

        remaining_capital   -= calc_monthly_capital
        calc_paid_capital   += calc_monthly_capital
        calc_remaining_int  -= calc_monthly_interests
        calc_paid_interests += calc_monthly_interests

        time_table << LoanCreator::TimeTable.new(
          term:                            term + 1 + self.deferred_in_months,
          monthly_payment:                 rounded_monthly_payment,
          monthly_payment_capital_share:   calc_monthly_capital,
          monthly_payment_interests_share: calc_monthly_interests,
          remaining_capital:               remaining_capital,
          paid_capital:                    calc_paid_capital,
          remaining_interests:             calc_remaining_int,
          paid_interests:                  calc_paid_interests
        )
      end

      last_interests_payment =
        (remaining_capital * self.monthly_interests_rate).round

      last_capital_payment =
        (last_payment - last_interests_payment).round

      remaining_capital -= last_capital_payment

      last_interests_payment -= remaining_capital
      last_capital_payment   += remaining_capital

      calc_paid_capital   += last_capital_payment
      calc_remaining_int  -= last_interests_payment
      calc_paid_interests += last_interests_payment

      # last time table term
      time_table << LoanCreator::TimeTable.new(
        term:                            self.duration_in_months,
        monthly_payment:                 last_payment,
        monthly_payment_capital_share:   last_capital_payment,
        monthly_payment_interests_share: last_interests_payment,
        remaining_capital:               0,
        paid_capital:                    calc_paid_capital,
        remaining_interests:             calc_remaining_int,
        paid_interests:                  calc_paid_interests
      )

      time_table
    end

    def calc_monthly_payment(amount=self.amount_in_cents,
        duration=self.duration_in_months)
      _calc_monthly_payment(amount, duration)
    end

    def calc_total_payment(amount)
      self.calc_monthly_payment(amount)
        .mult(BigDecimal.new(self.duration_in_months, @@accuracy), @@accuracy)
    end

    def rounded_monthly_payment(amount)
      self.calc_monthly_payment(amount).round
    end

    def total_rounded_payment(amount)
      (self.rounded_monthly_payment(amount) *
        BigDecimal.new(self.duration_in_months, @@accuracy)).round
    end

    def total_payment
      @total_payment ||= _total_payment
    end

    def total_interests
      @total_interests ||= _total_interests
    end

    def monthly_interests(amount)
      _monthly_interests(amount)
    end

    def deferred_total_interests(amount)
      _deferred_total_interests(amount)
    end

    def rounded_monthly_interests(amount)
      self.monthly_interests(amount).round
    end

    def deferred_total_rounded_interests(amount)
      _deferred_total_rounded_interests(amount)
    end

    def defer_period_difference(amount)
      _defer_period_difference(amount)
    end

    def monthly_capital_share(amount)
      _monthly_capital_share(amount)
    end

    def rounded_monthly_capital_share(amount)
      self.monthly_capital_share(amount).round
    end

    def precise_difference(amount)
      _precise_difference(amount)
    end

    private

    #          Capital * monthly_interests_rate
    # ____________________________________________________
    #  (1 - ((1 + monthly_interests_rate)^(-total_terms)))
    #
    def _calc_monthly_payment(amount, duration)
      denominator = (BigDecimal.new(1, @@accuracy) -
        ((BigDecimal.new(1, @@accuracy) + self.monthly_interests_rate) **
        ((BigDecimal.new(-1, @@accuracy))
        .mult(BigDecimal.new(duration, @@accuracy), @@accuracy))))

      BigDecimal.new(amount, @@accuracy)
        .mult(self.monthly_interests_rate, @@accuracy)
        .div(denominator, @@accuracy)
    end

    # total_terms * calc_monthly_payment
    #
    def _total_payment
      (BigDecimal.new(self.duration_in_months, @@accuracy)
        .mult((self.calc_monthly_payment).round, @@accuracy)) +
        (BigDecimal.new(self.deferred_in_months, @@accuracy)
        .mult(self.monthly_interests(self.amount_in_cents), @@accuracy))
    end

    # calc_total_payment - amount_in_cents
    #
    def _total_interests
      self.total_payment - BigDecimal.new(self.amount_in_cents, @@accuracy)
    end

    # Capital (arg) * monthly_interests_rate
    #
    def _monthly_interests(amount)
      BigDecimal.new(amount, @@accuracy)
        .mult(self.monthly_interests_rate, @@accuracy)
    end

    # monthly_interests * deferred_in_months
    #
    def _deferred_total_interests(amount)
      return 0 unless self.deferred_in_months > 0
      self.monthly_interests(amount)
        .mult(BigDecimal.new(self.deferred_in_months, @@accuracy), @@accuracy)
    end

    # rounded_monthly_interests * deferred_in_months
    #
    def _deferred_total_rounded_interests(amount)
      return 0 unless self.deferred_in_months > 0
      self.rounded_monthly_interests(amount) * deferred_in_months
    end

    # calculates the cumulated differece during deferred period
    #
    def _defer_period_difference(amount)
      self.deferred_total_rounded_interests(amount) -
        self.deferred_total_interests(amount)
    end

    # calc_monthly_payment * monthly_interests(capital)
    #
    def _monthly_capital_share(amount)
      self.calc_monthly_payment - self.monthly_interests(amount)
    end

    # difference between sum of precise mth pay and rounded ones
    #
    def _precise_difference(amount)
      # deferred period data
      defer_r_total_pay  = self.deferred_total_rounded_interests(amount)
      precise_difference = self.defer_period_difference(amount)

      # what should be paid
      precise_monthly_payment = self.calc_monthly_payment(amount)
      total_precise = self.calc_total_payment(amount)

      # what will be paid
      rounded_monthly_payment = self.rounded_monthly_payment(amount)
      total_rounded = self.total_rounded_payment(amount)

      precise_difference += total_rounded - total_precise
    end
  end
end
