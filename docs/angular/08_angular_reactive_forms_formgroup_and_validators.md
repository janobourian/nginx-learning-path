# Module 08: Strictly Typed Reactive Forms & Custom Validators

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** Form Engineering, Type Safety & Validation Pipelines

---

## 1. Strictly Typed Reactive Forms (Angular 14+)

Historically in Angular, `FormGroup.value` was typed as `any`. Accessing `form.get('email').value` returned an untyped value with zero IDE autocomplete or compile-time typo detection.

Modern Angular features **Strictly Typed Reactive Forms**:
- `FormControl<T>` enforces exact primitive or object types.
- `FormGroup<T>` infers the shape of all child controls.
- `FormArray<T>` provides typed dynamic array management.
- `FormRecord<T>` supports dynamic key-value dictionary forms.
- `NonNullableFormBuilder` ensures `.reset()` restores default values rather than resetting to `null`.

```typescript
// Strict Type Safety in Modern Angular:
const emailControl = new FormControl<string>("", { nonNullable: true });
// emailControl.value -> string (NOT string | null | undefined!)
```

---

## 2. Setting Up a Complex Typed Form with `NonNullableFormBuilder`

```typescript
// src/app/features/users/components/user-registration.component.ts
import { Component, inject } from "@angular/core";
import {
  NonNullableFormBuilder,
  ReactiveFormsModule,
  Validators,
  type AbstractControl,
  type ValidationErrors,
} from "@angular/forms";
import { CustomValidators } from "../validators/custom-validators";
import { UserValidationService } from "../services/user-validation.service";

@Component({
  selector: "app-user-registration",
  standalone: true,
  imports: [ReactiveFormsModule],
  templateUrl: "./user-registration.component.html",
  styleUrls: ["./user-registration.component.css"],
})
export class UserRegistrationComponent {
  private fb = inject(NonNullableFormBuilder);
  private userValidationService = inject(UserValidationService);

  // 1. Declare Strictly Typed FormGroup:
  public form = this.fb.group(
    {
      username: [
        "",
        [Validators.required, Validators.minLength(3), CustomValidators.alphanumeric],
        [this.userValidationService.uniqueUsernameValidator()], // Async Validator
      ],
      email: ["", [Validators.required, Validators.email]],
      passwords: this.fb.group(
        {
          password: ["", [Validators.required, Validators.minLength(8)]],
          confirmPassword: ["", [Validators.required]],
        },
        { validators: [CustomValidators.passwordMatch] } // Cross-field validator
      ),
      skills: this.fb.array<string>([]),
    }
  );

  // FormArray getter:
  public get skillsArray() {
    return this.form.controls.skills;
  }

  public addSkill(skillName: string): void {
    if (!skillName.trim()) return;
    this.skillsArray.push(this.fb.control(skillName, [Validators.required]));
  }

  public removeSkill(index: number): void {
    this.skillsArray.removeAt(index);
  }

  public onSubmit(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    // 100% Type-Safe Raw Value Extraction:
    const payload = this.form.getRawValue();
    console.log("Submitting valid payload:", payload);
  }
}
```

---

## 3. Custom Synchronous & Cross-Field Validators

### 1. Single Field Validator (`ValidatorFn`)

```typescript
// src/app/features/users/validators/custom-validators.ts
import { type AbstractControl, type ValidationErrors, type ValidatorFn } from "@angular/forms";

export class CustomValidators {
  // 1. Single Field Regex Validator
  public static alphanumeric: ValidatorFn = (control: AbstractControl): ValidationErrors | null => {
    if (!control.value) return null;
    const isValid = /^[a-zA-Z0-9_]+$/.test(control.value);
    return isValid ? null : { alphanumeric: { actualValue: control.value } };
  };

  // 2. Cross-Field Password Match Validator (Applied to child FormGroup)
  public static passwordMatch: ValidatorFn = (group: AbstractControl): ValidationErrors | null => {
    const password = group.get("password")?.value;
    const confirmPassword = group.get("confirmPassword")?.value;

    if (password && confirmPassword && password !== confirmPassword) {
      return { passwordMismatch: true };
    }
    return null;
  };
}
```

---

## 4. Debounced Asynchronous Validators (`AsyncValidatorFn`)

Asynchronous validators (e.g. verifying whether a username is already taken in the database) must return an `Observable<ValidationErrors | null>`. 

Always debounce async validators to prevent hitting the backend on every single keystroke:

```typescript
// src/app/features/users/services/user-validation.service.ts
import { Injectable, inject } from "@angular/core";
import { HttpClient } from "@angular/common/http";
import { type AsyncValidatorFn, type AbstractControl, type ValidationErrors } from "@angular/forms";
import { Observable, of, timer } from "rxjs";
import { switchMap, map, catchError } from "rxjs/operators";

@Injectable({ providedIn: "root" })
export class UserValidationService {
  private http = inject(HttpClient);

  public uniqueUsernameValidator(): AsyncValidatorFn {
    return (control: AbstractControl): Observable<ValidationErrors | null> => {
      if (!control.value || control.value.length < 3) {
        return of(null);
      }

      // Debounce HTTP validation check by 400ms:
      return timer(400).pipe(
        switchMap(() =>
          this.http.get<{ available: boolean }>(
            `/api/users/check-username?username=${encodeURIComponent(control.value)}`
          )
        ),
        map((response) => (response.available ? null : { usernameTaken: true })),
        catchError(() => of(null)) // Ignore network errors during validation
      );
    };
  }
}
```

---

## 5. Template Integration & Error Messages

```html
<!-- src/app/features/users/components/user-registration.component.html -->
<form [formGroup]="form" (ngSubmit)="onSubmit()" class="form-container">
  <h2>Create Enterprise Account</h2>

  <!-- Username Field with Async Validation Status -->
  <div class="form-field">
    <label for="username">Username</label>
    <input id="username" formControlName="username" />

    @if (form.controls.username.pending) {
      <span class="status-pending">Checking username availability...</span>
    }
    @if (form.controls.username.touched && form.controls.username.errors; as errs) {
      @if (errs['required']) { <span class="error">Username is required</span> }
      @if (errs['alphanumeric']) { <span class="error">Username can only contain letters, numbers, and underscores</span> }
      @if (errs['usernameTaken']) { <span class="error">Username is already taken</span> }
    }
  </div>

  <!-- Email Field -->
  <div class="form-field">
    <label for="email">Email Address</label>
    <input id="email" type="email" formControlName="email" />
    @if (form.controls.email.touched && form.controls.email.errors?.['email']) {
      <span class="error">Invalid email address format</span>
    }
  </div>

  <!-- Nested Passwords Group -->
  <div formGroupName="passwords" class="form-group-nested">
    <div class="form-field">
      <label for="password">Password</label>
      <input id="password" type="password" formControlName="password" />
    </div>

    <div class="form-field">
      <label for="confirmPassword">Confirm Password</label>
      <input id="confirmPassword" type="password" formControlName="confirmPassword" />
    </div>

    @if (form.controls.passwords.touched && form.controls.passwords.errors?.['passwordMismatch']) {
      <span class="error">Passwords do not match</span>
    }
  </div>

  <!-- Dynamic Skills FormArray -->
  <div class="skills-section">
    <h3>Developer Skills</h3>
    @for (skillControl of skillsArray.controls; track $index) {
      <div class="skill-row">
        <span>{{ skillControl.value }}</span>
        <button type="button" (click)="removeSkill($index)">Remove</button>
      </div>
    }
  </div>

  <button type="submit" [disabled]="form.pending" class="btn-submit">
    Register Account
  </button>
</form>
```

---

## Troubleshooting & Best Practices

1. **`getRawValue()` vs `.value`**
   - `form.value`: Excludes any controls that are currently **disabled** (`disabled: true`).
   - `form.getRawValue()`: Includes the values of **all controls, including disabled ones**. In 99% of enterprise scenarios, submit using `getRawValue()`.

2. **Always call `markAllAsTouched()` before validating submit**
   If a user clicks "Submit" immediately without focusing any fields, pristine invalid fields will not show error styles unless you call `this.form.markAllAsTouched()`.
