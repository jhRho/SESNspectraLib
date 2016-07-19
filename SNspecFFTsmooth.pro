PRO SNspecFFTsmooth, w, f, cut_vel, w_ft, f_ft, sep_vel

; For Release: Version 1.0, July 2016
; NAME:
;    SNspecFFTsmooth
; PURPOSE:
;    To smooth SN medium resolution spectrum by separating SN signal from noise in Fourier space
; CALLING SEQUENCE:
;   FFT_smooth, w, f, cut_vel, w_ft, f_ft, sep_vel
; INPUTS:
;   w = original wavelength, in angstrom (A)
;   f = original flux, in ergs/s/cm^2/A 
;   cut_vel = velocity below which we assume that velocities are inconsistent with the velocity of SN spectral 
;             features, in km/s, we find that 1000 km/s is a good working value for our data sets of SESNe (in Modjaz+16, Liu+16)
;              
;              
; OUTPUTS:
;   w_ft = wavelength corresponding to FFT smoothed flux
;   f_ft = FFT smoothed flux
;   sep_vel = velocity as determined in this code to separate SN spectral signal from the noise (in km/s)
;
; DEPENDENT PROCEDURE:
; binspec.pro (releaased as part of this repo)
; 
; WRITTEN BY: 
; Yuqian Liu and the NYUSNgroup (https://github.com/nyusngroup/SESNspectraLib/) and released under DOI XXX

!EXCEPT=2 ;allows IDL to report on the program context in which the error occurred, 
          ;along with the line number in the procedure.

;Define constant & parameter
c_kms                 = 299792.47 ; speed of light in km/s
vel_toolargeforSN_kms = 1.D5   ; Velocity limit for whose corresponding wavenumbers are not included in the fit 
                              ;as they are too large to be associated with SN features (see discussion in Appendix of Liu+16)

; convert to log(w) space
      w_ln=alog(w)                 
      num=n_elements(w_ln)
      binsize = (w_ln[num-1]-w_ln[num-2])
      f = f/(moment(f))[0]
      f_bin = binspec(w_ln,f,min(w_ln),max(w_ln),binsize,w_ln_bin) ;bin to same sampling interval in log(w) space
      f_bin=f_bin(where(f_bin NE 0))
      w_ln_bin=w_ln_bin(where(f_bin NE 0))
      num_bin=n_elements(f_bin)

; take flourier transform
      f_bin_ft=fft(f_bin,-1)*num_bin
; calculate frequency
      X = (FINDGEN((num_bin - 1)/2) + 1)
      is_N_even = (num_bin MOD 2) EQ 0
      if (is_N_even) then $
         freq = [0.0, X, num_bin/2, -num_bin/2 + X]/num_bin $
      else $
         freq = [0.0, X, -(num_bin/2 + 1) + X]/num_bin
         
; filter spectra    
      num_upper=max(where(1.0/freq[1:num_bin-1]* c_kms *binsize GT cut_vel))
      num_lower=max(where(1.0/freq[1:num_bin-1]* c_kms *binsize GT vel_toolargeforSN_kms, num_num_lower))
      f_bin_ft_line=fltarr(num_upper)
      
      ; average magnitudes with velocities between vel_toolargeforSN_kms and cut_vel      
      intercept=mean(abs(f_bin_ft(num_lower :num_upper)))
      f_bin_ft_line=(f_bin_ft_line+1.0)*intercept ; a straight line along x axis

      ; fit a power law to magnitudes with velocities smaller than 1.0e5 km/s
      g = linear_fit(alog(freq[num_lower :num_upper]), alog(f_bin_ft[num_lower :num_upper]))
      a = [10e1^(-g[0]/g[1]), g[1]]
      coeffs1=powerlaw_fit(freq(num_lower :num_bin/2), abs(f_bin_ft(num_lower :num_bin/2)), guess=a)

      ; find the intersection between average magnitudes and the power law fit
      delta=(freq(1:num_bin/2)/coeffs1[0])^coeffs1[1]-intercept

      ; if there is no intersection, then re-fit power law using different initial guess values
      if (max(delta) lt 0) and (num_upper*2 le num_bin/2) then begin
         ; initial guess      
         g = linear_fit(alog(freq[num_lower :num_upper*2]), alog(f_bin_ft[num_lower :num_upper*2]))
         a = [10e1^(-g[0]/g[1]), g[1]]
                  
         coeffs1=powerlaw_fit(freq(num_lower :num_bin/2), abs(f_bin_ft(num_lower :num_bin/2)),guess=a)
         delta=(freq(1:num_bin/2)/coeffs1[0])^coeffs1[1]-intercept 
      endif
      if max(delta) lt 0 then begin
         ; initial guess      
         g = linear_fit(alog(freq[num_lower*2:num_upper]), alog(f_bin_ft[num_lower*2:num_upper]))
         a = [10e1^(-g[0]/g[1]), g[1]]

         coeffs1=powerlaw_fit(freq(num_lower :num_bin/2), abs(f_bin_ft(num_lower :num_bin/2)),guess=a)
         delta=(freq(1:num_bin/2)/coeffs1[0])^coeffs1[1]-intercept 
      endif
      if max(delta) lt 0 then begin
         ; initial guess      
         g = linear_fit(alog(freq[num_lower :10*num_lower]), alog(f_bin_ft[num_lower :10*num_lower]))
         a = [10e1^(-g[0]/g[1]), g[1]]

         coeffs1=powerlaw_fit(freq(num_lower :num_bin/2), abs(f_bin_ft(num_lower :num_bin/2)),guess=a)
         delta=(freq(1:num_bin/2)/coeffs1[0])^coeffs1[1]-intercept 
      endif

      ; if there is still no intersection after trying a few initial guess values, then return, and let
      ; the user try a few more intial guess values
      if max(delta) lt 0 then begin
         print, 'try another initial guess value for power law fit'
         return
      endif

      ; find velocity that separates spectral signal from noise - by construction it will be between cut_vel and vel_toolargeforSN
      num_sep=min(where(delta LT 0)) 
      sep_vel=1.0/freq(num_sep)*3.0e5*binsize

      ; remove all magnitudes with velocities smaller than sep_vel, i.e., smooth
      f_bin_ft_smooth=f_bin_ft/num_bin
      for j=1L, num_bin do begin
         if j lt num_bin/2+1 then $
            number = j - 1 else $
               number = j - num_bin - 1
         numa = abs(number)
         if numa gt num_sep then begin
            f_bin_ft_smooth[j-1]=0
         endif
      endfor    
     
      ; take the inverse Fourier transform 
      f_bin_ft_smooth_inv=float(fft(f_bin_ft_smooth,1))
      
; output wavelength and FFT-smoothed flux
w_ft = exp(w_ln_bin)
f_ft = f_bin_ft_smooth_inv

END
