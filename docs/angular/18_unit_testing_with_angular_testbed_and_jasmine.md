# Module 18: Unit Testing Standalone Components, Signals & `TestBed`

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** Testing Architecture, TestBed & Signal Verification

---

## 1. Testing Standalone Components with `TestBed`

In modern Angular, configuring tests with `TestBed` is streamlined because components are standalone. You simply import the component directly under `imports: [...]` without configuring mock NgModules:

```typescript
// src/app/features/users/user-card.component.spec.ts
import { ComponentFixture, TestBed } from "@angular/core/testing";
import { UserCardComponent } from "./user-card.component";
import { By } from "@angular/platform-browser";

describe("UserCardComponent", () => {
  let component: UserCardComponent;
  let fixture: ComponentFixture<UserCardComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      // Import standalone component directly:
      imports: [UserCardComponent],
    }).compileComponents();

    fixture = TestBed.createComponent(UserCardComponent);
    component = fixture.componentInstance;
  });

  it("should create the component instance", () => {
    expect(component).toBeTruthy();
  });
});
```

---

## 2. Testing Signal Inputs (`fixture.componentRef.setInput()`)

When testing components that use `input()` or `input.required()`, use **`fixture.componentRef.setInput()`** to simulate parent input updates and trigger signal re-computation:

```typescript
// src/app/shared/components/badge.component.spec.ts
import { ComponentFixture, TestBed } from "@angular/core/testing";
import { BadgeComponent } from "./badge.component";

describe("BadgeComponent (Signal Inputs)", () => {
  let fixture: ComponentFixture<BadgeComponent>;
  let component: BadgeComponent;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [BadgeComponent],
    }).compileComponents();

    fixture = TestBed.createComponent(BadgeComponent);
    component = fixture.componentInstance;
  });

  it("should calculate computed uppercase label when signal input changes", () => {
    // 1. Set the signal input using setInput:
    fixture.componentRef.setInput("label", "production-ready");
    fixture.detectChanges();

    // 2. Assert component computed signal:
    expect(component.formattedLabel()).toBe("PRODUCTION-READY");

    // 3. Assert rendered DOM text:
    const compiled = fixture.nativeElement as HTMLElement;
    expect(compiled.querySelector(".badge-text")?.textContent).toContain("PRODUCTION-READY");
  });

  it("should apply active CSS class when boolean input is true", () => {
    fixture.componentRef.setInput("isActive", true);
    fixture.detectChanges();

    const badgeEl = fixture.nativeElement.querySelector(".badge");
    expect(badgeEl.classList.contains("badge--active")).toBeTrue();
  });
});
```

---

## 3. Mocking HTTP Requests with `provideHttpClientTesting()`

To test services and components that consume `HttpClient`, use the modern **`provideHttpClientTesting()`** provider:

```typescript
// src/app/core/services/user.service.spec.ts
import { TestBed } from "@angular/core/testing";
import { provideHttpClient } from "@angular/common/http";
import { provideHttpClientTesting, HttpTestingController } from "@angular/common/http/testing";
import { UserService, User } from "./user.service";

describe("UserService (HTTP Mocking)", () => {
  let service: UserService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        UserService,
        provideHttpClient(),
        provideHttpClientTesting(), // ◄── Injects HttpTestingController!
      ],
    });

    service = TestBed.inject(UserService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    // Verify that there are no unhandled / outstanding HTTP requests:
    httpMock.verify();
  });

  it("should fetch user by ID via GET request", () => {
    const mockUser: User = { id: "u_101", name: "Alice Chen", email: "alice@acme.com" };

    service.getUserById("u_101").subscribe((user) => {
      expect(user).toEqual(mockUser);
      expect(user.name).toBe("Alice Chen");
    });

    // Expect an outgoing request to /api/users/u_101:
    const req = httpMock.expectOne("/api/users/u_101");
    expect(req.request.method).toBe("GET");

    // Flush the mock response:
    req.flush(mockUser);
  });

  it("should handle HTTP 500 error gracefully", () => {
    service.getUserById("u_999").subscribe({
      next: () => fail("Expected an error, but received success response"),
      error: (error) => {
        expect(error.status).toBe(500);
      },
    });

    const req = httpMock.expectOne("/api/users/u_999");
    req.flush("Server Error", { status: 500, statusText: "Internal Server Error" });
  });
});
```

---

## 4. Testing Asynchronous Timers with `fakeAsync` & `tick()`

When testing debounced search inputs, polling timers, or `setTimeout` delays:

```typescript
// src/app/features/search/search-input.component.spec.ts
import { fakeAsync, tick, TestBed } from "@angular/core/testing";
import { SearchInputComponent } from "./search-input.component";

describe("SearchInputComponent (fakeAsync)", () => {
  it("should debounce search queries by 300ms", fakeAsync(() => {
    const fixture = TestBed.createComponent(SearchInputComponent);
    const component = fixture.componentInstance;
    fixture.detectChanges();

    spyOn(component.searchSubmitted, "emit");

    // Simulate typing:
    component.onInputChange("angular signals");

    // Advance virtual clock by 200ms (Debounce has NOT elapsed yet!):
    tick(200);
    expect(component.searchSubmitted.emit).not.toHaveBeenCalled();

    // Advance clock by remaining 100ms (Total: 300ms):
    tick(100);
    expect(component.searchSubmitted.emit).toHaveBeenCalledWith("angular signals");
  }));
});
```

---

## 5. Testing Functional Guards in Isolation

Functional route guards can be tested directly within `TestBed.runInInjectionContext()`:

```typescript
// src/app/core/guards/auth.guard.spec.ts
import { TestBed } from "@angular/core/testing";
import { Router, ActivatedRouteSnapshot, RouterStateSnapshot } from "@angular/router";
import { authGuard } from "./auth.guard";
import { AuthService } from "../services/auth.service";

describe("authGuard", () => {
  let authServiceMock: jasmine.SpyObj<AuthService>;
  let routerMock: jasmine.SpyObj<Router>;

  beforeEach(() => {
    authServiceMock = jasmine.createSpyObj("AuthService", ["isAuthenticated"]);
    routerMock = jasmine.createSpyObj("Router", ["createUrlTree"]);

    TestBed.configureTestingModule({
      providers: [
        { provide: AuthService, useValue: authServiceMock },
        { provide: Router, useValue: routerMock },
      ],
    });
  });

  it("should allow navigation when user is authenticated", () => {
    authServiceMock.isAuthenticated.and.returnValue(true);

    const result = TestBed.runInInjectionContext(() =>
      authGuard({} as ActivatedRouteSnapshot, { url: "/dashboard" } as RouterStateSnapshot)
    );

    expect(result).toBeTrue();
  });

  it("should redirect to /login when user is not authenticated", () => {
    authServiceMock.isAuthenticated.and.returnValue(false);

    TestBed.runInInjectionContext(() =>
      authGuard({} as ActivatedRouteSnapshot, { url: "/dashboard" } as RouterStateSnapshot)
    );

    expect(routerMock.createUrlTree).toHaveBeenCalledWith(["/login"], {
      queryParams: { returnUrl: "/dashboard" },
    });
  });
});
```

---

## Troubleshooting & Best Practices

1. **`TestBed.runInInjectionContext()` for Functional Helpers**
   Because functional guards, interceptors, and custom DI composables call `inject()`, always wrap their test execution in `TestBed.runInInjectionContext(() => fn())`.

2. **Never Call Real HTTP Endpoints in Tests**
   Always include `provideHttpClientTesting()` and call `httpMock.verify()` in `afterEach` to ensure tests remain fast, deterministic, and isolated.
