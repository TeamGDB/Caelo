package com.caelo.vpn

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.compose.ui.text.AnnotatedString
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AuthFlowTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun resetAccount() {
        composeRule.activity.getSharedPreferences("caelo_prefs", 0).edit().clear().commit()
        composeRule.activityRule.scenario.recreate()
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodes(hasText("Добро пожаловать")).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun backFromRegistrationClearsEnteredCredentials() {
        composeRule.onNodeWithText("Регистрация").performClick()
        composeRule.onNode(hasText("Логин") and hasSetTextAction()).performTextInput("temporary")
        composeRule.onNode(hasText("Пароль") and hasSetTextAction()).performTextInput("secret")
        composeRule.onNodeWithContentDescription("Назад").performClick()
        composeRule.onNodeWithText("Регистрация").performClick()

        val isEmpty = SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(""))
        composeRule.onNode(hasText("Логин") and hasSetTextAction()).assert(isEmpty)
        composeRule.onNode(hasText("Пароль") and hasSetTextAction()).assert(isEmpty)
    }

    @Test
    fun builtInAdminCanSignIn() {
        composeRule.onNodeWithText("Вход").performClick()
        composeRule.onNode(hasText("Логин") and hasSetTextAction()).performTextInput("admin")
        composeRule.onNode(hasText("Пароль") and hasSetTextAction()).performTextInput("admin")
        composeRule.onNodeWithText("Войти", useUnmergedTree = true).performClick()

        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodes(hasText("Текущий сервер")).fetchSemanticsNodes().isNotEmpty()
        }
    }
}
